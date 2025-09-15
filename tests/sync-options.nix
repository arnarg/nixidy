{
  lib,
  config,
  ...
}:
let
  apps = config.applications.apps.resources.applications;
in
{
  applications = {
    # Create an application with all sync options set
    test1.syncPolicy.syncOptions = {
      serverSideApply = true;
      replace = true;
      pruneLast = true;
      failOnSharedResource = true;
      applyOutOfSyncOnly = true;
    };

    # Create an application with some sync options set
    test2.syncPolicy.syncOptions = {
      serverSideApply = true;
      pruneLast = true;
      applyOutOfSyncOnly = true;
    };

    # Create an application with no sync options set
    test3 = { };
  };

  test = with lib; {
    name = "sync options";
    description = "Check that sync options are set correctly.";
    assertions = [
      {
        description = "Application with all sync options should set them correctly.";
        expression = apps.test1.spec.syncPolicy.syncOptions;
        assertion =
          opts:
          (compareLists compare opts [
            "ApplyOutOfSyncOnly=true"
            "FailOnSharedResource=true"
            "PruneLast=true"
            "Replace=true"
            "ServerSideApply=true"
          ]) == 0;
      }
      {
        description = "Application with some sync options should set them correctly.";
        expression = apps.test2.spec.syncPolicy.syncOptions;
        assertion =
          opts:
          (compareLists compare opts [
            "ApplyOutOfSyncOnly=true"
            "PruneLast=true"
            "ServerSideApply=true"
          ]) == 0;
      }
      {
        description = "Application with no sync options should set them correctly.";
        expression = apps.test3.spec.syncPolicy.syncOptions;
        assertion = isNull;
      }
    ];
  };
}
