{
  lib,
  pkgs,
  config,
  ...
}: let
  envName = lib.replaceStrings ["/"] ["-"] config.nixidy.target.branch;

  mkApp = app: let
    resources =
      map (obj: rec {
        filename = "${obj.kind}-${builtins.replaceStrings ["."] ["-"] obj.metadata.name}.yaml";
        manifest = let
          resource = builtins.toJSON obj;
        in
          pkgs.stdenv.mkDerivation {
            inherit resource;

            name = "nixidy-app-${app.name}-${filename}";

            passAsFile = ["resource"];

            phases = ["installPhase"];

            installPhase = ''
              cat $resourcePath | ${pkgs.yq-go}/bin/yq -P > $out
            '';
          };
      })
      app.objects;
  in
    pkgs.stdenv.mkDerivation {
      name = "nixidy-app-${app.name}";

      phases = ["installPhase"];

      installPhase =
        ''
          mkdir -p $out
        ''
        + (lib.concatStringsSep "\n" (map (res: ''
            ln -s ${res.manifest} $out/${res.filename}
          '')
          resources));
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

      extrasPackage = pkgs.linkFarm "nixidy-extras-${envName}" (
        lib.mapAttrsToList (
          _: file: {
            name = file.path;
            path = file.source;
          }
        )
        config.nixidy.extraFiles
      );

      environmentPackage = let
        joined = pkgs.linkFarm "nixidy-apps-joined-${envName}" (
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
          name = "nixidy-environment-${envName}";
          paths = [
            joined
            config.build.extrasPackage
          ];
        };

      activationPackage = pkgs.stdenv.mkDerivation {
        name = "nixidy-activation-environment-${envName}";
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

            ${pkgs.rsync}/bin/rsync --recursive --delete -L "${config.build.environmentPackage}/" "\$dest"

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
