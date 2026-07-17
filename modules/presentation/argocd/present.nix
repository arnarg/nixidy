# ArgoCD synthesis: the app-of-apps + bootstrap synthetic apps.
#
# A pure function `ctx -> { <appOfApps> = ...; __bootstrap = ...; }`. It reads its
# argocd config from `ctx.argocd` (the relocated `appOfApps`/`defaults` config,
# spliced in by ./default.nix's registry entry) and the target/env/apps from the
# shared synthesis `ctx`. It writes the synthetic apps' argocd fields directly;
# `mkApplication` reads only option-set fields of an app (never its
# `resources.applications`), so `present` never reads back its own output.
ctx:
let
  inherit (ctx) lib argocd;

  mkApplication = app: {
    metadata = {
      name =
        if (ctx.appendNameWithEnv && argocd.name != app.name) then "${app.name}-${ctx.env}" else app.name;
      annotations = if app.annotations != { } then app.annotations else null;
      labels = if app.labels != { } then app.labels else null;
      finalizers = lib.mkMerge [
        (lib.mkIf (app.argocd.finalizer == "background") (
          lib.singleton "resources-finalizer.argocd.argoproj.io/background"
        ))
        (lib.mkIf (app.argocd.finalizer == "foreground") (
          lib.singleton "resources-finalizer.argocd.argoproj.io"
        ))
      ];
    };
    spec = {
      inherit (app.argocd) project ignoreDifferences;

      source = {
        repoURL = ctx.target.repository;
        targetRevision = ctx.target.branch;
        path = lib.path.subpath.join [
          ctx.target.rootPath
          app.output.path
        ];
      };
      destination = lib.mkMerge [
        { inherit (app) namespace; }
        (lib.mkIf (app.argocd.destination.name != null) {
          inherit (app.argocd.destination) name;
        })
        (lib.mkIf (app.argocd.destination.name == null) {
          inherit (app.argocd.destination) server;
        })
      ];
      syncPolicy =
        (lib.optionalAttrs app.argocd.syncPolicy.autoSync.enable {
          automated = {
            inherit (app.argocd.syncPolicy.autoSync) prune selfHeal;
          };
        })
        // (lib.optionalAttrs (lib.length app.argocd.syncPolicy.finalSyncOpts > 0) {
          syncOptions = app.argocd.syncPolicy.finalSyncOpts;
        })
        // (lib.optionalAttrs (app.argocd.syncPolicy.managedNamespaceMetadata != null) {
          inherit (app.argocd.syncPolicy) managedNamespaceMetadata;
        })
        // (lib.optionalAttrs (app.argocd.syncPolicy.retry != null) {
          inherit (app.argocd.syncPolicy) retry;
        });
    };
  };

  # Lower priority than `mkDefault`, higher priority than `mkOptionDefault`.
  mkLowerDefault = lib.mkOverride 1100;
in
{
  "${argocd.name}" = {
    inherit (argocd) namespace;
    argocd = {
      inherit (argocd) project destination;

      # App of apps autoSync should (probably) automatically be enabled.
      syncPolicy.autoSync = {
        enable = mkLowerDefault true;
        prune = mkLowerDefault true;
        selfHeal = mkLowerDefault true;
      };
    };

    resources.applications =
      let
        appsWithoutAppsOfApps = lib.filter (n: n != argocd.name) ctx.publicApps;
      in
      builtins.listToAttrs (
        map (name: {
          inherit name;
          value = mkApplication ctx.apps.${name};
        }) appsWithoutAppsOfApps
      );
  };

  # This application's resources are printed on stdout when
  # `nixidy bootstrap .#<env>` is run.
  __bootstrap = {
    inherit (argocd) namespace;
    argocd = { inherit (argocd) project; };

    resources.applications.${argocd.name} = mkApplication ctx.apps.${argocd.name};
  };
}
