{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (config.nixidy) env;
  mkApp = app: let
    writeManifests =
      ''
        set -e

        out=$1

      ''
      + (lib.concatStringsSep "\n" (map (obj: let
          filename = "${obj.kind}-${builtins.replaceStrings ["."] ["-"] obj.metadata.name}.yaml";
        in ''
          echo "Writing ${filename}"

          cat <<'EOF' | ${pkgs.yq-go}/bin/yq -P > $out/${filename}
          ${builtins.toJSON obj}
          EOF
        '')
        app.objects));
  in
    pkgs.stdenv.mkDerivation {
      inherit writeManifests;

      name = "nixidy-app-${app.name}";

      passAsFile = ["writeManifests"];

      phases = ["installPhase"];

      installPhase = ''
        mkdir -p $out

        sh $writeManifestsPath $out
      '';
    };
in {
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
    };
  };

  config = {
    build = {
      bootstrapPackage = mkApp config.applications.__bootstrap;

      extrasPackage = pkgs.linkFarm "nixidy-extras-${env}" (
        lib.mapAttrsToList (
          _: file: {
            name = file.path;
            path = file.source;
          }
        )
        config.nixidy.extraFiles
      );

      environmentPackage = let
        joined = pkgs.linkFarm "nixidy-apps-joined-${env}" (
          map (name: let
            app = config.applications.${name};
          in {
            name = app.output.path;
            path = mkApp app;
          })
          config.nixidy.publicApps
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
        phases = ["installPhase"];

        installPhase = ''
          mkdir -p $out

          ln -s ${config.build.environmentPackage} $out/environment

          cat <<EOF > $out/activate
          #!/usr/bin/env bash
          set -eo pipefail
          dest="${config.nixidy.target.rootPath}"

          mkdir -p "\$dest"

          # We need to check if there is a difference between
          # the newly built environment and the destination
          # excluding ".revision" because that will most likely
          # always change when going through CI, avoiding infinite
          # loop.
          if ! ${pkgs.diffutils}/bin/diff -q -r --exclude .revision "${config.build.environmentPackage}" "\$dest" &>/dev/null; then
            echo "switching manifests"

            ${pkgs.rsync}/bin/rsync \
              --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r \
              --recursive --delete --copy-links \
              "${config.build.environmentPackage}/" "\$dest"

            echo "done!"
          else
            echo "no changes!"
          fi
          EOF

          chmod +x $out/activate
        '';
      };

      declarativePackage = let
        apps =
          lib.filterAttrs
          (n: _: n != config.nixidy.appOfApps.name && !(lib.hasPrefix "__" n))
          config.applications;

        labelPrefix = "apps.nixidy.dev";

        classify = obj:
          if obj.kind == "CustomResourceDefinition"
          then "crds"
          else if obj.kind == "Namespace"
          then "namespaces"
          else "manifests";

        labelObjects = app: objs:
          map (
            obj: let
              label = "${labelPrefix}/${classify obj}";
            in
              obj
              // {
                metadata =
                  obj.metadata
                  // {
                    labels =
                      (obj.metadata.labels or {})
                      // {
                        "${labelPrefix}/application" = app;
                        "${label}" = env;
                      };
                  };
              }
          )
          objs;

        manifests = with lib;
          pipe apps
          [
            (mapAttrsToList (_: app:
              labelObjects
              app.name
              app.objects))
            flatten
            (groupBy classify)
            builtins.toJSON
          ];
      in
        pkgs.stdenv.mkDerivation {
          inherit manifests;

          name = "nixidy-declarative-package-${env}";

          passAsFile = ["manifests"];

          phases = ["installPhase"];

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
