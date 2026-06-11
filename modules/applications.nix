{
  lib,
  config,
  ...
}:
let
  # The selectable Kubernetes versions are exactly the generated resource
  # modules present in ./generated/k8s (each `nixidy.k8sVersion` value `X.Y`
  # imports `./generated/k8s/vX.Y.nix`). Deriving the enum from the artifacts on
  # disk keeps it in sync with what can actually be imported, rather than
  # reaching into the generator's `versions.nix` acquisition spec.
  versions = lib.pipe ./generated/k8s [
    builtins.readDir
    builtins.attrNames
    (builtins.filter (lib.hasSuffix ".nix"))
    (map (n: lib.removeSuffix ".nix" (lib.removePrefix "v" n)))
  ];
in
{
  options = with lib; {
    applications = mkOption {
      type =
        with types;
        attrsOf (submoduleWith {
          modules = [
            ./applications
          ]
          ++ config.nixidy.applicationImports
          ++ config.nixidy.presentation.perAppModules;
          specialArgs.nixidyDefaults = config.nixidy.defaults;
        });
      default = { };
      description = ''
        An application is a single Argo CD application that will be rendered by nixidy.

        The resources will be rendered into it's own directory and an Argo CD application created for it.
      '';
      example = {
        nginx = {
          namespace = "nginx";
          resources = {
            deployments.nginx.spec = {
              replicas = 3;
              selector.matchLabels.app = "nginx";
              template = {
                metadata.labels.app = "nginx";
                spec = {
                  securityContext.fsGroup = 1000;
                  containers.nginx = {
                    image = "nginx:1.25.1";
                    imagePullPolicy = "IfNotPresent";
                  };
                };
              };
            };

            services.nginx.spec = {
              selector.app = "nginx";
              ports.http.port = 80;
            };
          };
        };
      };
    };

    nixidy = {
      k8sVersion = mkOption {
        type = with types; enum versions;
        default = "1.35";
        description = "The Kubernetes version for generated resource options to use.";
      };
      applicationImports = mkOption {
        type =
          with types;
          listOf (oneOf [
            package
            path
            (functionTo attrs)
          ]);
        default = [ ];
        description = "List of modules to import into `applications.*` submodule (most useful for resource definition options).";
      };
      baseImports = mkOption {
        type = with types; bool;
        default = true;
        internal = true;
        visible = false;
        description = "Controls if the default applicationImports should be included or not. Used by options documentation generation.";
      };
    };
  };

  config = lib.mkIf config.nixidy.baseImports {
    nixidy.applicationImports = [
      ./generated/k8s/v${config.nixidy.k8sVersion}.nix
    ];
  };
}
