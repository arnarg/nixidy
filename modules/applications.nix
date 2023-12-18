{
  lib,
  config,
  ...
}: let
  global = config;

  setPriority = pri: resources: lib.mapAttrsRecursive (_: val: lib.mkOverride pri val) resources;

  helmOpts = with lib;
    ns: {
      name,
      config,
      ...
    }: {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Name of the helm release.";
        };
        namespace = mkOption {
          type = types.str;
          default = ns;
          defaultText = literalExpression "config.applications.<name>.namespace";
          description = "Namespace for the release.";
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
        transformer = mkOption {
          type = with types; functionTo (listOf (attrsOf anything));
          default = global.nixidy.defaults.helm.transformer;
          defaultText = literalExpression "config.nixidy.defaults.helm.transformer";
          example = literalExpression ''
            map (lib.kube.removeLabels ["helm.sh/chart"])
          '';
          description = ''
            Function that will be applied to the list of rendered manifests after the helm templating.
          '';
        };
        rendered = mkOption {
          type = types.attrsOf (types.attrsOf (types.attrsOf types.anything));
          default = {};
          internal = true;
          description = "Rendered helm chart and parsed into nixidy format.";
        };
      };

      config.rendered = lib.pipe {inherit (config) name namespace chart values includeCRDs;} [
        lib.helm.buildHelmChart
        builtins.readFile
        lib.kube.fromYAML
        config.transformer
        lib.resources.fromManifests
      ];
    };

  kustomizeOpts = with lib;
    ns: {
      name,
      config,
      ...
    }: {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Name of the kustomize application.";
        };
        namespace = mkOption {
          type = types.str;
          default = ns;
          defaultText = literalExpression "config.applications.<name>.namespace";
          description = "Namespace for the kustomize application.";
        };
        kustomization = {
          src = mkOption {
            type = types.package;
            description = "Derivation containing all the kustomize bases and overlays.";
          };
          path = mkOption {
            type = types.str;
            description = "Path relative to the base of `src` to the entrypoint kustomization directory.";
          };
        };
        transformer = mkOption {
          type = with types; functionTo (listOf (attrsOf anything));
          default = res: res;
          defaultText = literalExpression "res: res";
          description = ''
            Function that will be applied to the list of rendered manifest from kustomize.
          '';
        };
        rendered = mkOption {
          type = types.attrsOf (types.attrsOf (types.attrsOf types.anything));
          default = {};
          internal = true;
          description = "Rendered kustomization and parsed into nixidy format.";
        };
      };

      config.rendered =
        lib.pipe {
          inherit (config) name namespace;
          inherit (config.kustomization) src path;
        } [
          lib.kustomize.buildKustomization
          builtins.readFile
          lib.kube.fromYAML
          config.transformer
          lib.resources.fromManifests
        ];
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
              default = global.nixidy.defaults.syncPolicy.automated.prune;
              defaultText = literalExpression "config.nixidy.defaults.syncPolicy.automated.prune";
              description = ''
                Specifies if resources should be pruned during auto-syncing.
              '';
            };
            selfHeal = mkOption {
              type = types.bool;
              default = global.nixidy.defaults.syncPolicy.automated.selfHeal;
              defaultText = literalExpression "config.nixidy.defaults.syncPolicy.automated.selfHeal";
              description = ''
                Specifies if partial app sync should be executed when resources are changed only in
                target Kubernetes cluster and no git change detected.
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
            type = types.attrsOf (types.submodule (helmOpts config.namespace));
            default = {};
            description = ''
              Helm releases to template and add to the rendered application's resources.
            '';
          };
        };
        kustomize = {
          applications = mkOption {
            type = types.attrsOf (types.submodule (kustomizeOpts config.namespace));
            default = {};
            example = literalExpression ''
              {
                argocd = {
                  namespace = "argocd";
                  # Equivalent to `github.com/argoproj/argo-cd/manifests/cluster-install?ref=v2.9.3`
                  # in kustomization.yaml.
                  kustomization = {
                    src = pkgs.fetchFromGitHub {
                      owner = "argoproj";
                      repo = "argo-cd";
                      rev = "v2.9.3";
                      hash = "sha256-GaY4Cw/LlSwy35umbB4epXt6ev8ya19UjHRwhDwilqU=";
                    };
                    path = "manifests/cluster-install";
                  };
                };
              };
            '';
            description = ''
              Kustomize applications to render and add to the rendered application's resources.
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
          ++ (lib.mapAttrsToList (n: v: (
              setPriority 900 v.rendered
            ))
            config.helm.releases)
          ++ (lib.mapAttrsToList (n: v: (
              setPriority 900 v.rendered
            ))
            config.kustomize.applications));
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
