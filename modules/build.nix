{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (config.nixidy) env;

  # Apply eval-time `rewrite` rules to a list of objects, in declaration order.
  # A rule whose predicate matches rewrites the object via `rewrite`; returning
  # null drops the object. Rules without `rewrite` (i.e. `postProcess`) are
  # ignored here.
  applyRewrites =
    rules: objs:
    let
      rewrites = lib.filter (r: r.rewrite != null) rules;
    in
    lib.concatMap (
      obj:
      let
        out = lib.foldl' (
          o: r:
          if o == null then
            null
          else if r.predicate o then
            r.rewrite o
          else
            o
        ) obj rewrites;
      in
      lib.optional (out != null) out
    ) objs;

  # Per-app objects after eval-time rewrite transforms: env rules first, then
  # app rules.
  transformedObjects =
    app: applyRewrites app.objectTransforms (applyRewrites config.nixidy.objectTransforms app.objects);

  # The on-disk group key / filename stem for an object. mkApp groups objects
  # under this key; post-process rules resolve the matching path from the same
  # helper, and yamls.nix reuses it to detect raw-passthrough collisions, so the
  # filename policy lives in exactly one place (applications/lib.nix).
  groupKeyOf = helpers.objectBaseName;

  # All transform rules visible to an app: env rules first, then app rules
  # (chained in that order, matching `applyRewrites`).
  allRules = app: config.nixidy.objectTransforms ++ app.objectTransforms;

  # Post-process rules matching a (post-rewrite) object, in env-then-app order.
  postProcessRulesFor =
    app: obj: lib.filter (r: r.postProcess != null && r.predicate obj) (allRules app);

  # The on-disk relative path (within the environment package, and therefore
  # within both the staging tree and the deploy target) for a post-rewrite
  # object: <app.output.path>/<groupKey>.yaml.
  objPath = app: obj: "${app.output.path}/${groupKeyOf obj}.yaml";

  # Label prefix and resource classifier shared by declarativePackage (for its
  # selector labels) and applyFiles (for the apply path's per-file class).
  labelPrefix = "apps.nixidy.dev";

  classify =
    obj:
    if obj.kind == "CustomResourceDefinition" then
      "crds"
    else if obj.kind == "Namespace" then
      "namespaces"
    else
      "manifests";

  # Public apps deployed imperatively by `apply`: every app except the
  # app-of-apps app and internal __-prefixed apps (matches declarativePackage).
  applyApps = lib.filterAttrs (
    n: _: n != config.nixidy.appOfApps.name && !(lib.hasPrefix "__" n)
  ) config.applications;

  # One entry per rendered resource file in environmentPackage that apply
  # deploys. `path` addresses the file inside environmentPackage (mkApp layout).
  applyFiles = lib.concatMap (
    app:
    lib.mapAttrsToList (
      groupKey: objs:
      let
        firstObj = builtins.head objs;
      in
      {
        path = "${app.output.path}/${groupKey}.yaml";
        class = classify firstObj;
        app = app.name;
        rules = postProcessRulesFor app firstObj;
        resource = firstObj;
      }
    ) (builtins.groupBy groupKeyOf (transformedObjects app))
  ) (lib.attrValues applyApps);

  # Files whose chain runs at apply time (for the up-front notice/listing).
  applyChainFiles = lib.filter (f: f.rules != [ ]) applyFiles;

  applyPostProcessListing = pkgs.writeText "nixidy-apply-post-process-listing-${env}" (
    lib.concatMapStrings (
      f:
      "  ${f.path}:\n"
      + lib.concatMapStrings (
        r: "    ${lib.optionalString (r.name != null) "${r.name}: "}${resolveCommand f.path f.resource r}\n"
      ) f.rules
    ) applyChainFiles
  );

  # Up-front notice + TTY prompt. NOT gated on NIXIDY_SKIP_POST_PROCESS (apply
  # always post-processes). Runtime $ is heredoc-escaped (\''${…}, \$).
  applyPostProcessNotice = lib.optionalString (applyChainFiles != [ ]) ''
    echo "post-processing ${toString (lib.length applyChainFiles)} manifest file(s); the following commands run outside any sandbox. Review them before continuing:"
    cat ${applyPostProcessListing}
    if [ "\''${NIXIDY_POST_PROCESS_APPROVE:-}" != "1" ] && [ -t 0 ]; then
      printf 'Continue with post-processing? [y/N] '
      read -r _nixidy_pp_reply
      case "\$_nixidy_pp_reply" in
        [yY] | [yY][eE][sS]) ;;
        *)
          echo "aborted; nothing applied." >&2
          exit 1
          ;;
      esac
    fi
  '';

  # Per-file stream: clean environmentPackage file → add prune labels (BEFORE the
  # chain) → chain if the file has rules. yq labels every document in the file.
  applyFileStream =
    f:
    let
      labelExpr = ''.metadata.labels."${labelPrefix}/application" = "${f.app}" | .metadata.labels."${labelPrefix}/${f.class}" = "${env}"'';
      labeled = ''cat "${config.build.environmentPackage}/${f.path}" | ${pkgs.yq-go}/bin/yq -P '${labelExpr}' '';
    in
    if f.rules == [ ] then labeled else "${labeled} | ${chainOf f.path f.resource f.rules}";

  applyClass =
    class: pruneAllowlist:
    let
      files = lib.filter (f: f.class == class) applyFiles;
      allowlistFlag = lib.optionalString (
        pruneAllowlist != null
      ) ''--prune-allowlist "${pruneAllowlist}"'';
      stream =
        if files == [ ] then
          "printf -- '---\\n'"
        else
          lib.concatMapStringsSep "\n        printf -- '---\\n'\n        " applyFileStream files;
    in
    ''
      echo "Applying ${class}"
      {
        ${stream}
      } | ${pkgs.kubectl}/bin/kubectl apply -f - \
        --prune --selector "${labelPrefix}/${class}=${env}" ${allowlistFlag}
    '';

  # The generated `apply` script body (consumes environmentPackage, runs
  # postProcess, streams to `kubectl apply -f -` per class). Factored out so
  # `build._applyScript` can expose it for regression tests of the generated
  # bash.
  applyScript = ''
    #!/usr/bin/env bash
    set -eo pipefail

    ${applyPostProcessNotice}

    ${applyClass "crds" "apiextensions.k8s.io/v1/CustomResourceDefinition"}
    ${applyClass "namespaces" "core/v1/Namespace"}
    ${applyClass "manifests" null}
  '';

  # Per-app post-process entries: one { path; resource; rules; } per
  # post-rewrite object with at least one matching post-process rule.
  # `postProcessRulesFor` is computed once per object here. `resource` is
  # carried so function-form post-process commands can resolve against it.
  postProcessEntriesFor =
    app:
    lib.concatMap (
      obj:
      let
        rules = postProcessRulesFor app obj;
      in
      lib.optional (rules != [ ]) {
        path = objPath app obj;
        resource = obj;
        inherit rules;
      }
    ) (transformedObjects app);

  # Per-app map: on-disk relative path -> { resource; rules; }.
  filePostProcesses =
    app:
    lib.listToAttrs (
      map (e: lib.nameValuePair e.path { inherit (e) resource rules; }) (postProcessEntriesFor app)
    );

  # Flatten every app's filePostProcesses into a single { path -> rules } map
  # for the environment. Within an app, the uniqueness assertion guarantees no
  # path collisions. Across apps, paths cannot collide because each app's paths
  # are prefixed by its distinct `app.output.path` (mkApp's linkFarm name).
  allFilePostProcesses = lib.foldl' (acc: app: acc // filePostProcesses app) { } (
    lib.attrValues config.applications
  );

  # Resolve a rule's post-process command against a matched object: function-form
  # commands are applied to the resource; a literal snippet is used verbatim.
  # Shared by the activation block (compiles it to a script) and the up-front
  # notice (prints it), so what is shown is exactly what runs.
  resolveCommand =
    path: resource: r:
    if lib.isFunction r.postProcess.command then
      r.postProcess.command {
        inherit resource path pkgs;
        inherit (pkgs) lib;
      }
    else
      r.postProcess.command;

  # Build the `cmd1 | cmd2 | …` chain of writeShellApplication store paths for a
  # group's postProcess rules. `cmdPath` keys the script names and is the on-disk
  # path passed to function-form commands. Shared by the switch block and (later)
  # the apply script.
  chainOf =
    cmdPath: resource: rules:
    let
      scriptOf =
        i: r:
        pkgs.writeShellApplication {
          name = "nixidy-post-process-${
            builtins.replaceStrings [ "/" "." ] [ "-" "-" ] cmdPath
          }-${toString i}";
          runtimeInputs = r.postProcess.runtimeInputs;
          # Verbatim command body; invoked by store path (no `sh -c` requote).
          text = resolveCommand cmdPath resource r;
        };
    in
    lib.concatMapStringsSep " | " (s: lib.getExe s) (lib.imap0 scriptOf rules);

  # Activation post-process block for a single (path, rules) entry: rewrite the
  # staged file in place via the chained rule commands, honoring
  # NIXIDY_SKIP_POST_PROCESS.
  postProcessBlock =
    path:
    { resource, rules }:
    let
      chain = chainOf path resource rules;
      # Named rules in the chain, for the activation log.
      ruleNames = lib.filter (n: n != null) (map (r: r.name) rules);
      label = path + lib.optionalString (ruleNames != [ ]) " (${lib.concatStringsSep ", " ruleNames})";
    in
    ''
      if [ "\''${NIXIDY_SKIP_POST_PROCESS:-}" = "1" ]; then
        mkdir -p "\$(dirname "\$staging/${path}")"
        if [ -f "\$dest/${path}" ]; then
          cp "\$dest/${path}" "\$staging/${path}"
        else
          rm -f "\$staging/${path}"
        fi
      else
        echo "Post-processing ${label}"
        mkdir -p "\$(dirname "\$staging/${path}")"
        TARGET_PATH="\$dest/${path}" ${chain} \
          < "\$staging/${path}" > "\$staging/${path}.tmp" \
          && mv "\$staging/${path}.tmp" "\$staging/${path}"
      fi
    '';

  postProcessBlocks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList postProcessBlock allFilePostProcesses
  );

  # Up-front activation notice: print every post-process command about to run,
  # against which file, once before any command executes. These commands run
  # outside any sandbox, so this is visibility (not a gate) for the "switching to
  # someone else's config is code execution" case. Showing the actual command
  # (not just a rule name) is the honest signal for a due-diligence bail.
  # Rendered to a store file and `cat`ed so arbitrary command text needs no
  # heredoc escaping. Skipped under NIXIDY_SKIP_POST_PROCESS, where nothing runs.
  postProcessListing = pkgs.writeText "nixidy-post-process-listing-${env}" (
    lib.concatStrings (
      lib.mapAttrsToList (
        path:
        { resource, rules }:
        "  ${path}:\n"
        + lib.concatMapStrings (
          r: "    ${lib.optionalString (r.name != null) "${r.name}: "}${resolveCommand path resource r}\n"
        ) rules
      ) allFilePostProcesses
    )
  );

  postProcessNotice =
    let
      fileCount = lib.length (lib.attrNames allFilePostProcesses);
    in
    ''
      if [ "\''${NIXIDY_SKIP_POST_PROCESS:-}" != "1" ]; then
        echo "post-processing ${toString fileCount} manifest file(s); the following commands run outside any sandbox. Review them before continuing:"
        cat ${postProcessListing}
        # Pause for confirmation only when stdin is a terminal: a piped/CI/
        # pre-commit run is non-interactive and proceeds untouched, so
        # automation never blocks. NIXIDY_POST_PROCESS_APPROVE=1 skips the prompt
        # for trusted, repeated interactive use. This is informed-consent UX, not
        # a security boundary (the config defining the rule can set the approval
        # variable too); the point is to surface an unsandboxed postProcess
        # command to a human switching to a config they have not vetted.
        if [ "\''${NIXIDY_POST_PROCESS_APPROVE:-}" != "1" ] && [ -t 0 ]; then
          printf 'Continue with post-processing? [y/N] '
          read -r _nixidy_pp_reply
          case "\$_nixidy_pp_reply" in
            [yY] | [yY][eE][sS]) ;;
            *)
              echo "aborted; no changes written." >&2
              exit 1
              ;;
          esac
        fi
      fi
    '';

  helpers = import ./applications/lib.nix lib;

  mkApp =
    app:
    let
      grouped = builtins.groupBy groupKeyOf (transformedObjects app);

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
        description = "Internal: per-application objects after eval-time rewrite transforms (for tests).";
      };
      _filePostProcesses = mkOption {
        internal = true;
        readOnly = true;
        type = types.attrsOf (types.attrsOf types.anything);
        default = lib.mapAttrs (_: filePostProcesses) config.applications;
        description = "Internal: per-app output-path -> { resource; rules; } (for tests).";
      };
      _applyFiles = mkOption {
        internal = true;
        readOnly = true;
        type = types.listOf types.attrs;
        default = applyFiles;
      };
      _applyScript = mkOption {
        internal = true;
        readOnly = true;
        type = types.str;
        default = applyScript;
        description = "Internal: the generated `apply` script body (for tests).";
      };
    };
  };

  config = {
    # Per-app: post-processed file paths must be unique. `listToAttrs` collapses
    # colliding keys, so a count mismatch means two post-processed objects share
    # an on-disk file (group-key collision); post-processing a multi-document
    # file is undefined. Emitted as a single env-scope assertion naming the
    # offender.
    nixidy.assertions =
      let
        colliding = lib.filter (
          app: lib.length (postProcessEntriesFor app) != lib.length (lib.attrNames (filePostProcesses app))
        ) (lib.attrValues config.applications);
      in
      [
        {
          assertion = colliding == [ ];
          message =
            "objectTransforms postProcess rules collide on a shared on-disk file in application(s): "
            + lib.concatMapStringsSep ", " (app: "`${app.name}`") colliding
            + " (group-key collision among post-processed objects); post-processing a multi-document file is undefined.";
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

        installPhase =
          let
            rsyncFlags = "--chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r --recursive --delete --copy-links";

            # No post-process rules: sync the built environment straight to the
            # target, skipping all work when nothing changed (excluding
            # .revision, which churns through CI and would otherwise loop).
            directSwitch = ''
              if ! ${pkgs.diffutils}/bin/diff -q -r --exclude .revision "${config.build.environmentPackage}" "\$dest" &>/dev/null; then
                echo "switching manifests"
                ${pkgs.rsync}/bin/rsync ${rsyncFlags} "${config.build.environmentPackage}/" "\$dest"
                echo "done!"
              else
                echo "no changes!"
              fi
            '';

            # Post-process rules present: stage the environment, run the rules
            # over the matched files, then sync the staging tree to the target.
            # NIXIDY_SKIP_POST_PROCESS=1 preserves the existing post-processed
            # target files (re-use what is on disk instead of re-processing).
            stagedSwitch = ''
              echo "switching manifests"

              ${postProcessNotice}

              staging=\$(mktemp -d)
              trap 'rm -rf "\$staging"' EXIT
              cp -rL --no-preserve=mode "${config.build.environmentPackage}"/. "\$staging"/

              ${postProcessBlocks}

              ${pkgs.rsync}/bin/rsync ${rsyncFlags} "\$staging/" "\$dest"

              echo "done!"
            '';
          in
          ''
            mkdir -p $out

            ln -s ${config.build.environmentPackage} $out/environment

            cat <<EOF > $out/activate
            #!/usr/bin/env bash
            set -eo pipefail
            dest="${config.nixidy.target.rootPath}"

            mkdir -p "\$dest"

            ${if allFilePostProcesses == { } then directSwitch else stagedSwitch}
            EOF

            chmod +x $out/activate
          '';
      };

      declarativePackage = pkgs.stdenv.mkDerivation {
        name = "nixidy-declarative-package-${env}";
        phases = [ "installPhase" ];
        installPhase = ''
          mkdir -p $out

          cat <<EOF > $out/apply
          ${applyScript}
          EOF

          chmod +x $out/apply
        '';
      };
    };
  };
}
