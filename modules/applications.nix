{
  lib,
  config,
  ...
}: let
  global = config;

  setPriority = pri: resources: lib.mapAttrsRecursive (_: val: lib.mkOverride pri val) resources;

  helmOpts = with lib;
    {name, ...}: {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Name of the helm release.";
        };
        namespace = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Namespace for the release. When set to `null` it will use the application's namespace.";
        };
        chart = mkOption {
          type = types.package;
          description = ''
            Derivation containing the helm chart for the release.
          '';
        };
        values = mkOption {
          type = types.attrsOf types.anything;
          default = {};
          description = ''
            Values to pass to the helm chart when rendering it.
          '';
        };
        includeCRDs = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether or not to include CRDs in the helm release.
          '';
        };
      };
    };

  appOpts = with lib;
    {
      name,
      config,
      ...
    }: {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Name of the application.";
        };
        namespace = mkOption {
          type = types.str;
          default = name;
          description = "Namespace to deploy application into (defaults to name).";
        };
        createNamespace = mkOption {
          type = types.bool;
          default = false;
          description = "Whether or not a namespace resource should be automatically created.";
        };
        project = mkOption {
          type = types.str;
          default = "default";
          description = "ArgoCD project to make application a part of.";
        };
        syncPolicy = {
          automated = {
            prune = mkOption {
              type = types.bool;
              default = global.nixidy.defaultSyncPolicy.automated.prune;
              description = ''
                Specifies if resources should be pruned during auto-syncing.

                Defaults to `config.nixidy.defaultSyncPolicy.automated.prune`.
              '';
            };
            selfHeal = mkOption {
              type = types.bool;
              default = global.nixidy.defaultSyncPolicy.automated.selfHeal;
              description = ''
                Specifies if partial app sync should be executed when resources are changed only in target
                Kubernetes cluster and no git change detected.

                Defaults to `config.nixidy.defaultSyncPolicy.automated.selfHeal`.
              '';
            };
          };
        };
        output = {
          path = mkOption {
            type = types.str;
            default = name;
            description = ''
              Name of the folder that contains all rendered resources for the application. Relative to the root of the repository.
            '';
          };
        };
        helm = {
          releases = mkOption {
            type = types.attrsOf (types.submodule helmOpts);
            default = {};
            description = ''
              Helm releases to template and add to the rendered application's resources.
            '';
          };
        };
        yamls = mkOption {
          type = types.listOf types.str;
          default = [];
          example = [
            ''
              apiVersion: v1
              kind: Namespace
              metadata:
                name: default
            ''
          ];
          description = ''
            List of Kubernetes manifests declared in YAML strings. They will be parsed and added to the application's
            `resources` where they can be overwritten and modified.

            Can be useful for reading existing YAML files (i.e. `[(builtins.readFile ./deployment.yaml)]`).
          '';
        };
        manifests = mkOption {
          type = types.listOf (types.attrsOf types.anything);
          default = [];
          example = [
            {
              apiVersion = "v1";
              kind = "Namespace";
              metadata.name = "default";
            }
          ];
          description = ''
            List of Kubernetes manifests in nix attribute sets. They will be parsed and added to the application's
            `resources` where they can be overwritten and modified.

            Can be useful for using helper functions in `lib.kube`.
          '';
        };
        resources = mkOption {
          type = types.attrsOf (types.attrsOf (types.attrsOf types.anything));
          default = {};
          example = {
            v1 = {
              Namespace.argocd = {};
              ConfigMap.argocd-cmd-params-cm = {
                metadata.namespace = "argocd";
                data."server.insecure" = "true";
              };
            };
          };
          description = ''
            Resources that make up the application.

            They should be declared in the form `<apiVersion>.<kind>.<name>`.

            For example the following namespace resource:

            ```yaml
            apiVersion: v1
            kind: Namespace
            metadata:
              name: argocd
              labels:
                pod-security.kubernetes.io/enforce: privileged
            ```

            Would be declared in like this:

            ```nix
            {
              v1.Namespace.argocd = {
                metadata.labels."pod-security.kubernetes.io/enforce" = "privileged";
              };
            }
            ```
          '';
        };
      };

      config = {
        resources = lib.mkMerge ([
            (setPriority 500
              (lib.resources.fromManifests config.manifests))
            (setPriority 700
              (lib.resources.fromManifestYAMLs config.yamls))
            (lib.optionalAttrs config.createNamespace {v1.Namespace.${config.namespace} = {};})
          ]
          ++ (lib.mapAttrsToList (n: v: (setPriority 900
            (lib.resources.fromHelmChart {
              inherit (v) name chart values includeCRDs;
              namespace =
                if (isNull v.namespace)
                then config.namespace
                else v.namespace;
            })))
          config.helm.releases));
      };
    };
in {
  options.applications = with lib;
    mkOption {
      type = types.attrsOf (types.submodule appOpts);
      default = {};
      description = ''
        An application is a single Argo CD application that will be rendered by nixidy.

        The resources will be rendered into it's own directory and an Argo CD application created for it.
      '';
      example = {
        argocd = {
          namespace = "argocd";
          resources = {
            v1.Namespace.argocd = {};
          };
        };
      };
    };
}
