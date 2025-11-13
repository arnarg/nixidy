{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  applications = {
    # Create an application without any retry.
    test1 = { };

    # Create an application with retry
    test2.syncPolicy.retry = {
      backoff = {
        duration = "5s";
        factor = 2;
        maxDuration = "3m";
      };
      limit = 5;
    };
  };

  test = with lib; {
    name = "argo-syncpolicy-retry";
    description = "Check that the ArgoCD Application has the correct retry";
    assertions = [
      {
        description = "Application without retry";
        expression = config.applications.apps.resources.applications.test1.spec.syncPolicy;
        assertion = sp: sp.retry == null;
      }
      {
        description = "Application with retry";
        expression = config.applications.apps.resources.applications.test2.spec.syncPolicy;
        assertion =
          sp:
          sp.retry != null
          && sp.retry.limit == 5
          && sp.retry.backoff.duration == "5s"
          && sp.retry.backoff.factor == 2
          && sp.retry.backoff.maxDuration == "3m";
      }
    ];
  };
}
