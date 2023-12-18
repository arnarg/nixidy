{
  modules,
  pkgs,
  kubelib,
  lib ? pkgs.lib,
  extraSpecialArgs ? {},
}: let
  extendedLib = import ../lib {inherit pkgs kubelib;};

  nixidyModules = import ./modules.nix;

  module = lib.evalModules {
    modules = modules ++ nixidyModules;
    specialArgs =
      {
        inherit pkgs;
        lib = extendedLib;
      }
      // extraSpecialArgs;
  };

  extras = pkgs.stdenv.mkDerivation {
    name = "nixidy-extras";

    phases = ["installPhase"];

    installPhase =
      ''
        mkdir -p $out
      ''
      + (
        lib.concatStringsSep "\n" (lib.mapAttrsToList (n: f: ''
            mkdir -p $out/$(dirname ${f.path})
            cat <<EOF > $out/${f.path}
            ${f.text}
            EOF
          '')
          module.config.nixidy.extraFiles)
      );
  };

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
    module.config.applications;

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

  mkStage = apps: let
    appsJoined = pkgs.linkFarm "nixidy-stage-apps-joined" (lib.mapAttrsToList (_: app: {
        name = app.path;
        path = mkApp app;
      })
      apps);
  in
    pkgs.symlinkJoin {
      name = "nixidy-stage";
      paths = [appsJoined extras];
    };
in {
  targetBranch = module.config.nixidy.target.branch;
  meta = {
    repository = module.config.nixidy.target.repository;
    branch = module.config.nixidy.target.branch;
  };
  result = mkStage apps;
}
