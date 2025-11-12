{
  lib,
  config,
  ...
}:
{
  # Create an application with everything default.
  applications.test.resources.namespaces.test1 = { };

  test = with lib; {
    name = "appOfApps-default-destination";
    description = "Check the logic of appOfApps destination vs application destinations.";
    assertions = [
      {
        description = "Default destination is applied to the appOfApps.";
        expression = config.applications.__bootstrap.resources.applications.apps.spec;
        assertion = spec: spec.destination.server == "https://kubernetes.default.svc";
      }
      {
        description = "Default destination is applied to the test application.";
        expression = config.applications.apps.resources.applications.test.spec;
        assertion = spec: spec.destination.server == "https://kubernetes.default.svc";
      }
    ];
  };
}
