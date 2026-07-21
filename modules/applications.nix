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
          specialArgs = {
            # Generic defaults (helm/kustomize) consumed by helm.nix/kustomize.nix.
            nixidyDefaults = config.nixidy.defaults;
            # ArgoCD per-app defaults (finalizer/syncPolicy/destination), owned by
            # the argocd backend, consumed by presentation/argocd/options.nix.
            argocdDefaults = config.nixidy.presentation.argocd.defaults;
          };
        });
      default = { };
      description = ''
        An application is a single unit of resources that nixidy renders into its
        own output directory.

        The active presentation backend (`nixidy.presentation.backend`) synthesizes
        the controller object for it (an ArgoCD `Application`, a Flux `Kustomization`, ...).
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
