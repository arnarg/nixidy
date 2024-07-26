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
    build.extrasPackage = mkOption {
      type = types.package;
      internal = true;
      description = "The package containing all the extra files for an environment.";
    };
    build.environmentPackage = mkOption {
      type = types.package;
      internal = true;
      description = "The package containing all the applications for an environment.";
    };
    build.activationPackage = mkOption {
      type = types.package;
      internal = true;
      description = "The package containing all the applications and an activation script.";
    };
  };

  config = {
    build.extrasPackage = pkgs.stdenv.mkDerivation {
      name = "nixidy-extras-${envName}";

      phases = ["installPhase"];

      installPhase =
        ''
          mkdir -p $out
        ''
        + (lib.concatStringsSep "\n" (lib.mapAttrsToList (_: file: ''
            mkdir -p $out/$(dirname ${file.path})
            cat <<EOF > "$out/${file.path}"
            ${file.text}
            EOF
          '')
          config.nixidy.extraFiles));
    };

    build.environmentPackage = let
      joined = pkgs.linkFarm "nixidy-apps-joined-${envName}" (lib.mapAttrsToList (_: app: {
          name = app.output.path;
          path = mkApp app;
        })
        config.applications);
    in
      pkgs.symlinkJoin {
        name = "nixidy-environment-${envName}";
        paths = [
          joined
          config.build.extrasPackage
        ];
      };

    build.activationPackage = pkgs.stdenv.mkDerivation {
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
        # excluding `.revision` because that will most likely
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
}
