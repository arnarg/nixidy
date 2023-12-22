{
  lib,
  config,
  pkgs,
  ...
}: let
  envName = lib.replaceStrings ["/"] ["-"] config.nixidy.target.branch;

  apps =
    lib.mapAttrs (
      n: v: {
        name = n;
        path = v.output.path;
        resources = lib.flatten (
          lib.mapAttrsToList (
            group: groupData:
              lib.mapAttrsToList (
                kind: kindData:
                  lib.mapAttrsToList (
                    res: resData:
                      resData
                      // {
                        apiVersion = group;
                        kind = kind;
                        metadata = {name = res;} // (resData.metadata or {});
                      }
                  )
                  kindData
              )
              groupData
          )
          v.resources
        );
      }
    )
    config.applications;

  mkApp = app: let
    resources =
      map (
        res: rec {
          filename = "${res.kind}-${builtins.replaceStrings ["."] ["-"] res.metadata.name}.yaml";
          manifest = let
            resource = builtins.toJSON res;
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
        }
      )
      app.resources;
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
    nixidy.extrasPackage = mkOption {
      type = types.package;
      internal = true;
      description = "The package containing all the extra files for an environment.";
    };

    nixidy.environmentPackage = mkOption {
      type = types.package;
      internal = true;
      description = "The package containing all the applications for an environment.";
    };
  };

  config = {
    # Build all extra files into its own package
    nixidy.extrasPackage = pkgs.stdenv.mkDerivation {
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

    # Build final environment into a package
    nixidy.environmentPackage = let
      joined = pkgs.linkFarm "nixidy-apps-joined-${envName}" (lib.mapAttrsToList (_: app: {
          name = app.path;
          path = mkApp app;
        })
        apps);
    in
      pkgs.symlinkJoin {
        name = "nixidy-environment-${envName}";
        paths = [
          joined
          config.nixidy.extrasPackage
        ];
      };
  };
}
