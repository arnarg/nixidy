{ lib, config, ... }:
let
  cfg = config.nixidy;

  mkApplication = app: {
    metadata = {
      name =
        if (cfg.appendNameWithEnv && cfg.appOfApps.name != app.name) then
          "${app.name}-${cfg.env}"
        else
          app.name;
      annotations = if app.annotations != { } then app.annotations else null;
      labels = if app.labels != { } then app.labels else null;
      finalizers = lib.mkMerge [
        (lib.mkIf (app.finalizer == "background") (
          lib.singleton "resources-finalizer.argocd.argoproj.io/background"
        ))
        (lib.mkIf (app.finalizer == "foreground") (lib.singleton "resources-finalizer.argocd.argoproj.io"))
      ];
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
  options.nixidy.appOfApps = with lib; {
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
  };
}
