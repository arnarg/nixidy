{
  lib,
  config,
  ...
}: let
  cfg = config.nixidy;

  extraFilesOpts = with lib;
    {name, ...}: {
      options = {
        path = mkOption {
          type = types.str;
          default = name;
          description = "Path of output file.";
        };
        text = mkOption {
          type = types.lines;
          description = "Text of the output file.";
        };
      };
    };
in {
  imports = [
    (lib.mkRenamedOptionModule ["nixidy" "defaults" "syncPolicy" "autoSync" "enabled"] ["nixidy" "defaults" "syncPolicy" "autoSync" "enable"])
  ];

  options.nixidy = with lib; {
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

    extraFiles = mkOption {
      type = types.attrsOf (types.submodule extraFilesOpts);
      default = {};
      description = ''
        Extra files to write in the generated stage.
      '';
    };

    defaults = {
      helm.transformer = mkOption {
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
        server = mkOption {
          type = types.str;
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
    };

    charts = mkOption {
      type = with types; attrsOf anything;
      default = {};
      description = "Attrset of derivations containing helm charts. This will be passed as `charts` to every module.";
    };
    chartsDir = mkOption {
      type = with types; nullOr path;
      default = null;
      description = "Path to a directory containing sub-directory structure that can be used to build a charts attrset. This will be passed as `charts` to every module.";
    };

    publicApps = mkOption {
      type = with types; listOf str;
      default = [];
      internal = true;
      description = ''
        List of the names of all applications that do not contain the internal `__` prefix.
      '';
    };
  };

  config = {
    applications.${cfg.appOfApps.name} = {
      inherit (cfg.appOfApps) namespace;

      resources.applications = let
        appsWithoutAppsOfApps = lib.filter (n: n != cfg.appOfApps.name) cfg.publicApps;
      in
        builtins.listToAttrs
        (map (
            name: let
              app = config.applications.${name};
            in {
              inherit name;

              value = {
                metadata = {
                  inherit (app) name;
                  annotations =
                    if app.annotations != {}
                    then app.annotations
                    else null;
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
                  destination = {
                    inherit (app) namespace;
                    inherit (app.destination) server;
                  };
                  syncPolicy =
                    (lib.optionalAttrs app.syncPolicy.autoSync.enable {
                      automated = {
                        inherit (app.syncPolicy.autoSync) prune selfHeal;
                      };
                    })
                    // (lib.optionalAttrs (lib.length app.syncPolicy.finalSyncOpts > 0) {
                      syncOptions = app.syncPolicy.finalSyncOpts;
                    });
                };
              };
            }
          )
          appsWithoutAppsOfApps);
    };

    # This application's resources are printed on
    # stdout when `nixidy bootstrap .#<env>` is run
    applications.__bootstrap = let
      app = config.applications.${cfg.appOfApps.name};
    in {
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
          destination = {
            inherit (app) namespace;
            inherit (app.destination) server;
          };
          # Maybe this should be configurable but
          # generally I think autoSync would be
          # desirable on the initial appOfApps.
          syncPolicy.automated = {
            prune = true;
            selfHeal = true;
          };
        };
      };
    };

    _module.args.charts = config.nixidy.charts;
    nixidy = {
      charts = lib.optionalAttrs (cfg.chartsDir != null) (lib.helm.mkChartAttrs cfg.chartsDir);

      extraFiles = lib.optionalAttrs (cfg.build.revision != null) {
        ".revision".text = cfg.build.revision;
      };

      publicApps =
        builtins.filter (n: !(lib.hasPrefix "__" n))
        (builtins.attrNames config.applications);
    };
  };
}
