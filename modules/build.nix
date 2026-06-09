{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (config.nixidy) env;

  # Apply eval-time `map` rules to a list of objects, in declaration order.
  # A rule whose predicate matches rewrites the object via `map`; `map`
  # returning null drops the object. Rules without `map` (i.e. `render`) are
  # ignored here.
  applyMaps =
    rules: objs:
    let
      maps = lib.filter (r: r.map != null) rules;
    in
    lib.concatMap (
      obj:
      let
        out = lib.foldl' (
          o: r:
          if o == null then
            null
          else if r.predicate o then
            r.map o
          else
            o
        ) obj maps;
      in
      lib.optional (out != null) out
    ) objs;

  # Per-app objects after eval-time map transforms: env rules first, then
  # app rules.
  transformedObjects =
    app: applyMaps app.objectTransforms (applyMaps config.nixidy.objectTransforms app.objects);

  # Sanitize a resource name the same way mkApp does when forming the
  # on-disk group key / filename.
  sanitize = n: builtins.replaceStrings [ "." ] [ "-" ] n;

  # All transform rules visible to an app: env rules first, then app rules
  # (chained in that order, matching `applyMaps`).
  allRules = app: config.nixidy.objectTransforms ++ app.objectTransforms;

  # Render rules matching a (post-map) object, in env-then-app order.
  renderRulesFor = app: obj: lib.filter (r: r.render != null && r.predicate obj) (allRules app);

  # The exact on-disk relative path (within the environment package, and
  # therefore within both the staging tree and the deploy target) for a
  # given post-map object. Must equal the path mkApp writes:
  #   <app.output.path>/<kind>-<sanitized name>.yaml
  objPath = app: obj: "${app.output.path}/${obj.kind}-${sanitize obj.metadata.name}.yaml";

  # Post-map objects of an app that have at least one matching render rule.
  renderMatchedObjs = app: lib.filter (obj: renderRulesFor app obj != [ ]) (transformedObjects app);

  # Per-app map: on-disk relative path -> chained list of render rules.
  fileRenders =
    app:
    lib.listToAttrs (
      map (obj: lib.nameValuePair (objPath app obj) (renderRulesFor app obj)) (renderMatchedObjs app)
    );

  # Flatten every app's fileRenders into a single { path -> rules } map for the
  # environment. Within an app, the uniqueness assertion guarantees no path
  # collisions. Across apps, paths cannot collide because each app's paths are
  # prefixed by its distinct `app.output.path` (mkApp's linkFarm name).
  allFileRenders = lib.foldl' (acc: app: acc // fileRenders app) { } (
    lib.attrValues config.applications
  );

  # Activation render block for a single (path, rules) entry: render the staged
  # file in place via the chained rule commands, honoring NIXIDY_SKIP_RENDER.
  renderBlock =
    path: rules:
    let
      nameFor = i: "nixidy-render-${builtins.replaceStrings [ "/" "." ] [ "-" "-" ] path}-${toString i}";
      scriptOf =
        i: r:
        pkgs.writeShellApplication {
          name = nameFor i;
          runtimeInputs = r.render.runtimeInputs;
          # Verbatim command body: quotes/$vars/pipes preserved. The script is
          # invoked by store path, so there is no `sh -c '...'` requote step.
          text = r.render.command;
        };
      scripts = lib.imap0 scriptOf rules;
      chain = lib.concatMapStringsSep " | " (s: lib.getExe s) scripts;
    in
    ''
      if [ "\''${NIXIDY_SKIP_RENDER:-}" = "1" ]; then
        mkdir -p "\$(dirname "\$staging/${path}")"
        if [ -f "\$dest/${path}" ]; then
          cp "\$dest/${path}" "\$staging/${path}"
        else
          rm -f "\$staging/${path}"
        fi
      else
        echo "Rendering ${path}"
        mkdir -p "\$(dirname "\$staging/${path}")"
        TARGET_PATH="\$dest/${path}" ${chain} \
          < "\$staging/${path}" > "\$staging/${path}.tmp" \
          && mv "\$staging/${path}.tmp" "\$staging/${path}"
      fi
    '';

  renderBlocks = lib.concatStringsSep "\n" (lib.mapAttrsToList renderBlock allFileRenders);

  mkApp =
    app:
    let
      grouped = builtins.groupBy (obj: "${obj.kind}-${sanitize obj.metadata.name}") (
        transformedObjects app
      );

      rawYamlFiles = map (source: {
        filename = baseNameOf source;
        inherit source;
      }) app.extraRawYamls;

      writeManifests = ''
        set -e
        out=$1

      ''
      + (lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          groupKey: objs:
          let
            filename = "${groupKey}.yaml";
          in
          if builtins.length objs == 1 then
            let
              obj = builtins.head objs;
            in
            ''
              echo "Writing ${filename}"
              cat <<'EOF' | ${pkgs.yq-go}/bin/yq -P > $out/${filename}
              ${builtins.toJSON obj}
              EOF
            ''
          else
            let
              sorted = lib.sort (a: b: (a.metadata.namespace or "") < (b.metadata.namespace or "")) objs;
            in
            ''
              echo "Writing ${filename}"
              cat <<'EOF' | ${pkgs.yq-go}/bin/yq '.[] | split_doc' -P > $out/${filename}
              ${builtins.toJSON sorted}
              EOF
            ''
        ) grouped
      ))
      + lib.optionalString (rawYamlFiles != [ ]) (
        "\n"
        + lib.concatMapStringsSep "\n" (f: ''
          echo "Writing ${f.filename}"
          cp ${f.source} "$out/${f.filename}"
        '') rawYamlFiles
      );
    in
    pkgs.stdenv.mkDerivation {
      inherit writeManifests;
      name = "nixidy-app-${app.name}";
      passAsFile = [ "writeManifests" ];
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out
        sh $writeManifestsPath $out
      '';
    };
in
{
  options = with lib; {
    build = {
      bootstrapPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing the bootstrap appOfApps application manifest.";
      };
      extrasPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing all the extra files for an environment.";
      };
      environmentPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing all the applications for an environment.";
      };
      activationPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing all the applications and an activation script.";
      };
      declarativePackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing manifests meant to be deployed directly using `kubectl apply --prune`.";
      };
      _transformedObjects = mkOption {
        internal = true;
        readOnly = true;
        type = types.attrsOf (types.listOf types.attrs);
        default = lib.mapAttrs (_: transformedObjects) config.applications;
        description = "Internal: per-application objects after eval-time map transforms (for tests).";
      };
      _fileRenders = mkOption {
        internal = true;
        readOnly = true;
        type = types.attrsOf (types.attrsOf types.anything);
        default = lib.mapAttrs (_: fileRenders) config.applications;
        description = "Internal: per-app output-path -> chained render rules (for tests).";
      };
    };
  };

  config = {
    # Per-app: rendered-file paths must be unique. `listToAttrs` collapses
    # colliding keys, so a count mismatch means two rendered objects share an
    # on-disk file (group-key collision); rendering over a multi-document file
    # is undefined. Emitted as a single env-scope assertion naming the offender.
    nixidy.assertions =
      let
        colliding = lib.filter (
          app: lib.length (renderMatchedObjs app) != lib.length (lib.attrNames (fileRenders app))
        ) (lib.attrValues config.applications);
      in
      [
        {
          assertion = colliding == [ ];
          message =
            "objectTransforms render rules collide on a shared on-disk file in application(s): "
            + lib.concatMapStringsSep ", " (app: "`${app.name}`") colliding
            + " (group-key collision among rendered objects); rendering over a multi-document file is undefined.";
        }
      ];

    build = {
      bootstrapPackage = mkApp config.applications.__bootstrap;

      extrasPackage = pkgs.linkFarm "nixidy-extras-${env}" (
        lib.mapAttrsToList (_: file: {
          name = file.path;
          path = file.source;
        }) config.nixidy.extraFiles
      );

      environmentPackage =
        let
          joined = pkgs.linkFarm "nixidy-apps-joined-${env}" (
            map (
              name:
              let
                app = config.applications.${name};
              in
              {
                name = app.output.path;
                path = mkApp app;
              }
            ) config.nixidy.publicApps
          );
        in
        pkgs.symlinkJoin {
          name = "nixidy-environment-${env}";
          paths = [
            joined
            config.build.extrasPackage
          ];
        };

      activationPackage = pkgs.stdenv.mkDerivation {
        name = "nixidy-activation-environment-${env}";
        phases = [ "installPhase" ];

        installPhase = ''
          mkdir -p $out

          ln -s ${config.build.environmentPackage} $out/environment

          cat <<EOF > $out/activate
          #!/usr/bin/env bash
          set -eo pipefail
          dest="${config.nixidy.target.rootPath}"

          mkdir -p "\$dest"

          echo "switching manifests"

          # Stage the built environment, then run any runtime render rules over
          # the matched files before syncing the staging tree to the target.
          # Set NIXIDY_SKIP_RENDER=1 to preserve the existing rendered target
          # files (re-use what is already on disk instead of re-rendering).
          staging=\$(mktemp -d)
          trap 'rm -rf "\$staging"' EXIT
          cp -rL --no-preserve=mode "${config.build.environmentPackage}"/. "\$staging"/

          ${renderBlocks}

          ${pkgs.rsync}/bin/rsync \
            --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r \
            --recursive --delete --copy-links \
            "\$staging/" "\$dest"

          echo "done!"
          EOF

          chmod +x $out/activate
        '';
      };

      declarativePackage =
        let
          apps = lib.filterAttrs (
            n: _: n != config.nixidy.appOfApps.name && !(lib.hasPrefix "__" n)
          ) config.applications;

          labelPrefix = "apps.nixidy.dev";

          classify =
            obj:
            if obj.kind == "CustomResourceDefinition" then
              "crds"
            else if obj.kind == "Namespace" then
              "namespaces"
            else
              "manifests";

          labelObjects =
            app: objs:
            map (
              obj:
              let
                label = "${labelPrefix}/${classify obj}";
              in
              obj
              // {
                metadata = obj.metadata // {
                  labels = (obj.metadata.labels or { }) // {
                    "${labelPrefix}/application" = app;
                    "${label}" = env;
                  };
                };
              }
            ) objs;

          manifests =
            with lib;
            pipe apps [
              (mapAttrsToList (_: app: labelObjects app.name (transformedObjects app)))
              flatten
              (groupBy classify)
              builtins.toJSON
            ];
        in
        pkgs.stdenv.mkDerivation {
          inherit manifests;

          name = "nixidy-declarative-package-${env}";

          passAsFile = [ "manifests" ];

          phases = [ "installPhase" ];

          installPhase = ''
            mkdir -p $out

            # Write different stages of manifests to YAML files
            cat $manifestsPath | \
              ${pkgs.yq-go}/bin/yq '.crds[] | split_doc' -P > $out/crds.yml
            cat $manifestsPath | \
              ${pkgs.yq-go}/bin/yq '.namespaces[] | split_doc' -P > $out/namespaces.yml
            cat $manifestsPath | \
              ${pkgs.yq-go}/bin/yq '.manifests[] | split_doc' -P > $out/manifests.yml

            # Write apply script
            cat <<EOF > $out/apply
            #!/usr/bin/env bash

            echo "Applying CRDs"
            ${pkgs.kubectl}/bin/kubectl apply \
              -f $out/crds.yml \
              --prune --selector "${labelPrefix}/crds=${env}" \
              --prune-allowlist "apiextensions.k8s.io/v1/CustomResourceDefinition"

            echo ""
            echo "Applying namespaces"
            ${pkgs.kubectl}/bin/kubectl apply \
              -f $out/namespaces.yml \
              --prune --selector "${labelPrefix}/namespaces=${env}" \
              --prune-allowlist "core/v1/Namespace"

            echo ""
            echo "Applying manifests"
            ${pkgs.kubectl}/bin/kubectl apply \
              -f $out/manifests.yml \
              --prune --selector "${labelPrefix}/manifests=${env}"
            EOF

            chmod +x $out/apply
          '';
        };
    };
  };
}
