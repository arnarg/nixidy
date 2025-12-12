{
  lib,
  config,
  ...
}:
let
  cfg = config.nixidy;

  mkApplication = app: {
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
    applications.${cfg.appOfApps.name} = {
      inherit (cfg.appOfApps) namespace project destination;

      # App of apps autoSync should (probably) automatically
      # be enabled
      syncPolicy.autoSync =
        let
          # Lower priority than `mkDefault`,
          # higher priority than `mkOptionDefault`.
          mkLowerDefault = lib.mkOverride 1100;
        in
        {
          enable = mkLowerDefault true;
          prune = mkLowerDefault true;
          selfHeal = mkLowerDefault true;
        };

      resources.applications =
        let
          appsWithoutAppsOfApps = lib.filter (n: n != cfg.appOfApps.name) cfg.publicApps;
        in
        builtins.listToAttrs (
          map (name: {
            inherit name;

            value = mkApplication config.applications.${name};
          }) appsWithoutAppsOfApps
        );
    };

    # This application's resources are printed on
    # stdout when `nixidy bootstrap .#<env>` is run
    applications.__bootstrap = {
      inherit (cfg.appOfApps) namespace project;

      resources.applications.${cfg.appOfApps.name} =
        mkApplication
          config.applications.${cfg.appOfApps.name};
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
