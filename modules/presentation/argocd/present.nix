# ArgoCD synthesis: the app-of-apps + bootstrap synthetic apps.
#
# Reads its config from `nixidy.presentation.argocd.*` (the relocated
# `appOfApps`/`defaults` config) and writes the synthetic apps' argocd fields to
# `applications.<name>.argocd.*` directly. Active only when the argocd backend is
# selected (imported from ./default.nix's `backend == "argocd"` guard).
{ lib, config, ... }:
let
  cfg = config.nixidy;
  argocd = cfg.presentation.argocd;

  helpers = import ../../applications/lib.nix lib;

  mkApplication = app: {
    metadata = {
      name =
        if (cfg.appendNameWithEnv && argocd.name != app.name) then "${app.name}-${cfg.env}" else app.name;
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
        repoURL = cfg.target.repository;
        targetRevision = cfg.target.branch;
        path = lib.path.subpath.join [
          cfg.target.rootPath
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

  bootstrapApplication = mkApplication config.applications.${argocd.name};
in
{
  config = lib.mkIf (cfg.presentation.backend == "argocd") {
    applications.${argocd.name} = {
      inherit (argocd) namespace;
      argocd = {
        inherit (argocd) project destination;

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
      };

      resources.applications =
        let
          appsWithoutAppsOfApps = lib.filter (n: n != argocd.name) cfg.publicApps;
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
      inherit (argocd) namespace;
      argocd = { inherit (argocd) project; };

      resources.applications.${argocd.name} = bootstrapApplication;
    };

    # The argocd backend owns the bootstrap manifest filename: the `__bootstrap`
    # app renders exactly one object — the app-of-apps `Application` — and
    # `build/` names each rendered file `<Kind>-<name>.yaml` via `objectBaseName`.
    # extra-files.nix reads this generic seam instead of hardcoding `Application-`.
    # The app-of-apps app's name is never env-suffixed (mkApplication suffixes
    # only when `app.name != argocd.name`), so this filename is stable.
    nixidy.presentation.bootstrapManifestFile = "${
      helpers.objectBaseName {
        kind = "Application";
        metadata.name = argocd.name;
      }
    }.yaml";
  };
}
