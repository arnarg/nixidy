{
  lib,
  config,
  ...
}: let
  cfg = config.nixidy;

  apps = builtins.removeAttrs config.applications [cfg.appOfApps.name];

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
  options.nixidy = with lib; {
    target = {
      repository = mkOption {
        type = types.str;
        description = "The repository URL to put in all generated applications.";
      };
      revision = mkOption {
        type = types.str;
        default = "HEAD";
        description = "The target revision to put in all generated applications.";
      };
    };

    extraFiles = mkOption {
      type = types.attrsOf (types.submodule extraFilesOpts);
      default = {};
      description = ''
        Extra files to write in the generated stage.
      '';
    };

    defaultSyncPolicy = {
      automated = {
        prune = mkOption {
          type = types.bool;
          default = false;
          description = "Specifies if resources should be pruned during auto-syncing. This is the default value for all applications if not explicitly set.";
        };
        selfHeal = mkOption {
          type = types.bool;
          default = false;
          description = "Specifies if partial app sync should be executed when resources are changed only in target Kubernetes cluster and no git change detected. This is the default value for all applications if not explicitly set.";
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
    };
  };

  config = {
    applications.${cfg.appOfApps.name} = {
      resources = {
        "argoproj.io/v1alpha1".Application =
          lib.attrsets.mapAttrs (
            n: app: {
              metadata.namespace = cfg.appOfApps.namespace;
              spec = {
                project = app.project;
                source = {
                  repoURL = cfg.target.repository;
                  targetRevision = cfg.target.revision;
                  path = app.output.path;
                };
                destination = {
                  server = "https://kubernetes.default.svc";
                  namespace = app.namespace;
                };
                syncPolicy.automated = {
                  prune = app.syncPolicy.automated.prune;
                  selfHeal = app.syncPolicy.automated.selfHeal;
                };
              };
            }
          )
          apps;
      };
    };
  };
}
