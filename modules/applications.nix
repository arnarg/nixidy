{
  lib,
  config,
  ...
}: let
  versions = lib.mapAttrsToList (
    version: _:
      builtins.concatStringsSep "." (lib.lists.sublist 0 2 (builtins.splitVersion version))
  ) (import ../pkgs/generators/versions.nix);
in {
  imports = [
    (lib.mkRenamedOptionModule ["nixidy" "resourceImports"] ["nixidy" "applicationImports"])
  ];

  options = with lib; {
    applications = mkOption {
      type = with types;
        attrsOf (submoduleWith {
          modules = [./applications] ++ config.nixidy.applicationImports;
          specialArgs.nixidyDefaults = config.nixidy.defaults;
        });
      default = {};
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
        default = "1.33";
        description = "The Kubernetes version for generated resource options to use.";
      };
      applicationImports = mkOption {
        type = with types; listOf (oneOf [package path (functionTo attrs)]);
        default = [];
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
      ./generated/argocd.nix
      ./generated/k8s/v${config.nixidy.k8sVersion}.nix
    ];
  };
}
