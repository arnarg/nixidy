{
  lib,
  config,
  ...
}:
{
  # Change the syncOptions for the appOfApps.
  nixidy.appOfApps.syncPolicy.syncOptions = {
    createNamespace = true;
    serverSideApply = true;
    replace = true;
    pruneLast = true;
    failOnSharedResource = true;
    applyOutOfSyncOnly = true;
  };

  # Create an application with everything default.
  applications.test.resources.namespaces.test = { };

  test = with lib; {
    name = "appOfApps-syncPolicy";
    description = "Check the logic of appOfApps sync policy";
    assertions = [
      {
        description = "App of apps should have autoSync enabled and selfHeal (default before exposing options)";
        expression = config.applications.__bootstrap.resources.applications.apps.spec.syncPolicy;
        assertion = policy: policy.automated.selfHeal;
      }
      {
        description = "App of apps should have the correct syncPolicy.syncOptions";
        expression =
          config.applications.__bootstrap.resources.applications.apps.spec.syncPolicy.syncOptions;
        assertion =
          opts:
          (compareLists compare opts [
            "ApplyOutOfSyncOnly=true"
            "CreateNamespace=true"
            "FailOnSharedResource=true"
            "PruneLast=true"
            "Replace=true"
            "ServerSideApply=true"
          ]) == 0;
      }
    ];
  };
}
