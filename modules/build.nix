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
  };
}
