{
  lib,
  config,
  ...
}:
let
  cfg = config.nixidy;

  nixidyDefaults = config.nixidy.defaults;

  # TODO: Consolidate with function in modules/applications/default.nix?
  convertSyncOptionsList =
    opts:
    let
      filtered = lib.filter (val: val != null) (lib.mapAttrsToList (_: val: val) opts);
    in
    filtered;
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "nixidy" "defaults" "syncPolicy" "autoSync" "enabled" ]
      [ "nixidy" "defaults" "syncPolicy" "autoSync" "enable" ]
    )
  ];

  options.nixidy = with lib; {
    env = mkOption {
      type = types.str;
      default = "default";
      description = "The environment name for this configuration.";
    };

    appendNameWithEnv = mkOption {
      type = types.bool;
      default = false;
      description = "When this is set to true, all applications names will be suffixed by the environment.";
    };

    target = {
      repository = mkOption {
        type = types.str;
        description = "The repository URL to put in all generated applications.";
      };
      branch = mkOption {
        type = types.str;
        description = "The destination branch of the generated applications.";
      };
      rootPath = mkOption {
        type = types.str;
        default = "./";
        description = "The root path of all generated applications in the repository.";
      };
    };

    build = {
      revision = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = literalExpression ''
          if (self ? rev) then self.rev else self.dirtyRev
        '';
        description = "The revision being built. Will be written to `.revision` in the environment destination directory.";
      };
    };

    defaults = {
      helm = {
        extraOpts = mkOption {
          type = with types; listOf str;
          default = [ ];
          example = [ "--no-hooks" ];
          description = ''
            The default extra options to pass to `helm template` that is run
            when rendering the helm chart, applies to all applications.
          '';
        };
        transformer = mkOption {
          type = with types; functionTo (listOf (attrsOf anything));
          default = res: res;
          defaultText = literalExpression "res: res";
          example = literalExpression ''
            map (lib.kube.removeLabels ["helm.sh/chart"])
          '';
          description = ''
            Function that will be applied to the list of rendered manifests after the helm templating.
            This option applies to all helm releases in all applications unless explicitly specified
            there.
          '';
        };
      };

      kustomize.transformer = mkOption {
        type = with types; functionTo (listOf (attrsOf anything));
        default = res: res;
        defaultText = literalExpression "res: res";
        example = literalExpression ''
          map (lib.kube.removeLabels ["app.kubernetes.io/version"])
        '';
        description = ''
          Function that will be applied to the list of rendered manifests after kustomize rendering.
          This option applies to all kustomize applications in all nixidy applications unless
          explicitly specified there.
        '';
      };

      syncPolicy = {
        autoSync = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if applications should automatically sync.

              This is the default value for all applications if not explicitly set for the application.
            '';
          };
          prune = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if resources should be pruned during auto-syncing.

              This is the default value for all applications if not explicitly set for the application.
            '';
          };
          selfHeal = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if partial app sync should be executed when resources are changed only in
              target Kubernetes cluster and no git change detected.

              This is the default value for all applications if not explicitly set for the application.
            '';
          };
        };
      };

      destination = {
        name = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            The name of the cluster that ArgoCD should deploy all applications to.

            This is the default value for all applications if not explicitly set for the application.
          '';
        };
        server = mkOption {
          type = types.nullOr types.str;
          default = "https://kubernetes.default.svc";
          description = ''
            The Kubernetes server that ArgoCD should deploy all applications to.

            This is the default value for all applications if not explicitly set for the application.
          '';
        };
      };
    };

    appOfApps = {
      name = mkOption {
        type = types.str;
        default = "apps";
        description = "Name of the application for bootstrapping all other applications (app of apps pattern).";
      };
      namespace = mkOption {
        type = types.str;
        default = "argocd";
        description = "Destination namespace for generated Argo CD Applications in the app of apps applications.";
      };
      project = mkOption {
        type = types.str;
        default = "default";
        description = "The project of the generated bootstrap app for appOfApps";
      };
      destination = {
        name = mkOption {
          type = types.nullOr types.str;
          default = cfg.defaults.destination.name;
          defaultText = literalExpression "config.nixidy.defaults.destination.name";
          description = ''
            The name of the cluster that ArgoCD should deploy the app of apps to.
          '';
        };
        server = mkOption {
          type = types.nullOr types.str;
          default = cfg.defaults.destination.server;
          defaultText = literalExpression "config.nixidy.defaults.destination.server";
          description = ''
            The Kubernetes server that ArgoCD should deploy the app of apps to.
          '';
        };
      };
      syncPolicy = {
        autoSync = {
          enable = mkOption {
            type = types.bool;
            # TODO: Honor the default?
            # default = nixidyDefaults.syncPolicy.autoSync.enable;
            # defaultText = literalExpression "config.nixidy.defaults.syncPolicy.autoSync.enable";
            default = true; # XXX: Previous behavior, worth keeping?
            description = ''
              Specifies if application should automatically sync.
            '';
          };
          prune = mkOption {
            type = types.bool;
            default = nixidyDefaults.syncPolicy.autoSync.prune;
            defaultText = literalExpression "config.nixidy.defaults.syncPolicy.autoSync.prune";
            description = ''
              Specifies if resources should be pruned during auto-syncing.
            '';
          };
          selfHeal = mkOption {
            type = types.bool;
            # TODO: Honor the default?
            # default = nixidyDefaults.syncPolicy.autoSync.selfHeal;
            # defaultText = literalExpression "config.nixidy.defaults.syncPolicy.autoSync.selfHeal";
            default = true; # XXX: Previous behavior, worth keeping?
            description = ''
              Specifies if partial app sync should be executed when resources are changed only in
              target Kubernetes cluster and no git change detected.
            '';
          };
        };
        managedNamespaceMetadata = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                annotations = mkOption {
                  type = types.nullOr (types.attrsOf types.str);
                  description = ''
                    Annotations to add to the ArgoCD managed namespace.
                  '';
                  default = null;
                };
                labels = mkOption {
                  type = types.nullOr (types.attrsOf types.str);
                  description = ''
                    Label to add to the ArgoCD managed namespace.
                  '';
                  default = null;
                };
              };

              config = { };
            }
          );
          default = null;
          description = ''
            ArgoCD Managed namespace metadata.
          '';
        };
        retry = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                backoff = mkOption {
                  type = types.nullOr (
                    types.submodule {
                      options = {
                        duration = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                        };
                        factor = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                        };
                        maxDuration = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                        };
                      };

                      config = { };
                    }
                  );

                  default = null;
                };

                limit = mkOption {
                  type = (types.nullOr types.int);
                  default = null;
                };
              };

              config = { };
            }
          );

          default = null;
          description = ''
            ArgoCD retry syncPolicy.
          '';
        };
        syncOptions = {
          applyOutOfSyncOnly = mkOption {
            type = types.bool;
            default = false;
            apply = val: if val then "ApplyOutOfSyncOnly=true" else null;
            description = ''
              Currently when syncing using auto sync Argo CD applies every object in the application.
              For applications containing thousands of objects this takes quite a long time and puts undue pressure on the api server.
              Turning on selective sync option which will sync only out-of-sync resources.
            '';
          };
          createNamespace = mkOption {
            type = types.bool;
            default = false;
            apply = val: if val then "CreateNamespace=true" else null;
            description = ''
              Namespace Auto-Creation ensures that namespace specified as the
              application destination exists in the destination cluster.
            '';
          };
          pruneLast = mkOption {
            type = types.bool;
            default = false;
            apply = val: if val then "PruneLast=true" else null;
            description = ''
              This feature is to allow the ability for resource pruning to happen as a final, implicit wave of a sync operation,
              after the other resources have been deployed and become healthy, and after all other waves completed successfully.
            '';
          };
          replace = mkOption {
            type = types.bool;
            default = false;
            apply = val: if val then "Replace=true" else null;
            description = ''
              By default, Argo CD executes `kubectl apply` operation to apply the configuration stored in Git.
              In some cases `kubectl apply` is not suitable. For example, resource spec might be too big and won't fit into
              `kubectl.kubernetes.io/last-applied-configuration` annotation that is added by kubectl apply.

              If the `replace = true;` sync option is set the Argo CD will use `kubectl replace` or `kubectl create` command
              to apply changes.
            '';
          };
          serverSideApply = mkOption {
            type = types.bool;
            default = false;
            apply = val: if val then "ServerSideApply=true" else null;
            description = ''
              By default, Argo CD executes `kubectl apply` operation to apply the configuration stored in Git.
              This is a client side operation that relies on `kubectl.kubernetes.io/last-applied-configuration` annotation to
              store the previous resource state.

              If `serverSideApply = true;` sync option is set, Argo CD will use `kubectl apply --server-side` command to apply changes.

              More info [here](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#server-side-apply).
            '';
          };
          failOnSharedResource = mkOption {
            type = types.bool;
            default = false;
            apply = val: if val then "FailOnSharedResource=true" else null;
            description = ''
              By default, Argo CD will apply all manifests found in the git path configured in the Application regardless if the
              resources defined in the yamls are already applied by another Application. If the `failOnSharedResource` sync option
              is set, Argo CD will fail the sync whenever it finds a resource in the current Application that is already applied in
              the cluster by another Application.
            '';
          };
        };
        finalSyncOpts = mkOption {
          type = types.listOf types.str;
          default = [ ];
          internal = true;
        };
      };
    };

    charts = mkOption {
      type = with types; attrsOf anything;
      default = { };
      description = "Attrset of derivations containing helm charts. This will be passed as `charts` to every module.";
    };
    chartsDir = mkOption {
      type = with types; nullOr path;
      default = null;
      description = "Path to a directory containing sub-directory structure that can be used to build a charts attrset. This will be passed as `charts` to every module.";
    };

    publicApps = mkOption {
      type = with types; listOf str;
      default = [ ];
      internal = true;
      description = ''
        List of the names of all applications that do not contain the internal `__` prefix.
      '';
    };
  };

  config = {
    nixidy.appOfApps.syncPolicy.finalSyncOpts = convertSyncOptionsList cfg.appOfApps.syncPolicy.syncOptions;

    applications.${cfg.appOfApps.name} = {
      inherit (cfg.appOfApps) namespace;

      resources.applications =
        let
          appsWithoutAppsOfApps = lib.filter (n: n != cfg.appOfApps.name) cfg.publicApps;
        in
        builtins.listToAttrs (
          map (
            name:
            let
              app = config.applications.${name};
            in
            {
              inherit name;

              value = {
                metadata = {
                  name = if cfg.appendNameWithEnv then "${app.name}-${cfg.env}" else app.name;
                  annotations = if app.annotations != { } then app.annotations else null;
                };
                spec = {
                  inherit (app) project ignoreDifferences;

                  source = {
                    repoURL = cfg.target.repository;
                    targetRevision = cfg.target.branch;
                    path = lib.path.subpath.join [
                      cfg.target.rootPath
                      app.output.path
                    ];
                  };
                  destination = lib.mkMerge [
                    { inherit (app) namespace; }
                    (lib.mkIf (app.destination.name != null) {
                      inherit (app.destination) name;
                    })
                    (lib.mkIf (app.destination.name == null) {
                      inherit (app.destination) server;
                    })
                  ];
                  syncPolicy =
                    (lib.optionalAttrs app.syncPolicy.autoSync.enable {
                      automated = {
                        inherit (app.syncPolicy.autoSync) prune selfHeal;
                      };
                    })
                    // (lib.optionalAttrs (lib.length app.syncPolicy.finalSyncOpts > 0) {
                      syncOptions = app.syncPolicy.finalSyncOpts;
                    })
                    // (lib.optionalAttrs (app.syncPolicy.managedNamespaceMetadata != null) {
                      inherit (app.syncPolicy) managedNamespaceMetadata;
                    })
                    // (lib.optionalAttrs (app.syncPolicy.retry != null) {
                      inherit (app.syncPolicy) retry;
                    });
                };
              };
            }
          ) appsWithoutAppsOfApps
        );
    };

    # This application's resources are printed on
    # stdout when `nixidy bootstrap .#<env>` is run
    applications.__bootstrap =
      let
        app = config.applications.${cfg.appOfApps.name};
      in
      {
        inherit (cfg.appOfApps) namespace;

        resources.applications.${cfg.appOfApps.name} = {
          metadata.namespace = cfg.appOfApps.namespace;
          spec = {
            inherit (cfg.appOfApps) project;

            source = {
              repoURL = cfg.target.repository;
              targetRevision = cfg.target.branch;
              path = lib.path.subpath.join [
                cfg.target.rootPath
                app.output.path
              ];
            };
            destination = lib.mkMerge [
              { inherit (app) namespace; }
              (lib.mkIf (cfg.appOfApps.destination.name != null) {
                inherit (cfg.appOfApps.destination) name;
              })
              (lib.mkIf (cfg.appOfApps.destination.name == null) {
                inherit (cfg.appOfApps.destination) server;
              })
            ];
            syncPolicy =
              (lib.optionalAttrs cfg.appOfApps.syncPolicy.autoSync.enable {
                automated = {
                  inherit (cfg.appOfApps.syncPolicy.autoSync) prune selfHeal;
                };
              })
              // (lib.optionalAttrs (lib.length cfg.appOfApps.syncPolicy.finalSyncOpts > 0) {
                syncOptions = cfg.appOfApps.syncPolicy.finalSyncOpts;
              })
              // (lib.optionalAttrs (cfg.appOfApps.syncPolicy.managedNamespaceMetadata != null) {
                inherit (cfg.appOfApps.syncPolicy) managedNamespaceMetadata;
              })
              // (lib.optionalAttrs (cfg.appOfApps.syncPolicy.retry != null) {
                inherit (cfg.appOfApps.syncPolicy) retry;
              });
          };
        };
      };

    _module.args.charts = config.nixidy.charts;
    nixidy = {
      charts = lib.optionalAttrs (cfg.chartsDir != null) (lib.helm.mkChartAttrs cfg.chartsDir);

      extraFiles = lib.optionalAttrs (cfg.build.revision != null) {
        ".revision".text = cfg.build.revision;
      };

      publicApps = builtins.filter (n: !(lib.hasPrefix "__" n)) (builtins.attrNames config.applications);
    };
  };
}
