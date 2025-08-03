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
    };
  };
}
