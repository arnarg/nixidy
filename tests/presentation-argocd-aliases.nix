{ lib, config, ... }:
{
  applications.viaold = {
    namespace = "test";
    # OLD top-level paths (pre-alias); mkRenamedOptionModule forwards them to .argocd.*
    syncPolicy = {
      autoSync.enable = true;
      syncOptions.replace = true;
    };
    project = "myproj";
    destination.name = "in-cluster";
  };
  applications.vianew = {
    namespace = "test";
    # NEW paths under .argocd.*
    argocd = {
      syncPolicy = {
        autoSync.enable = true;
        syncOptions.replace = true;
      };
      project = "myproj";
      destination.name = "in-cluster";
    };
  };
  test = with lib; {
    name = "argocd option aliases";
    description = "old top-level argocd paths value-forward to .argocd.*";
    assertions = [
      {
        description = "old syncPolicy.autoSync.enable forwards to .argocd.syncPolicy";
        expression = config.applications.viaold.argocd.syncPolicy.autoSync.enable;
        assertion = v: v;
      }
      {
        description = "old project forwards to .argocd.project";
        expression = config.applications.viaold.argocd.project;
        assertion = v: v == "myproj";
      }
      {
        description = "old destination.name forwards to .argocd.destination.name";
        expression = config.applications.viaold.argocd.destination.name;
        assertion = v: v == "in-cluster";
      }
      {
        description = "old deep syncOptions.replace forwards (and applies) to .argocd.syncPolicy";
        expression = config.applications.viaold.argocd.syncPolicy.syncOptions.replace;
        assertion = v: v == "Replace=true";
      }
      {
        description = "old and new paths render identically (finalSyncOpts)";
        expression = {
          old = config.applications.viaold.argocd.syncPolicy.finalSyncOpts;
          new = config.applications.vianew.argocd.syncPolicy.finalSyncOpts;
        };
        assertion = v: v.old == v.new;
      }
    ];
  };
}
