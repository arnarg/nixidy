{
  lib,
  config,
  ...
}:
let
  defaultServer = "https://localhost:6443";
in
{
  nixidy.defaults = {
    # Set the default destination server
    destination.server = defaultServer;
  };

  # Create an application with everything default.
  applications.test.resources.namespaces.test1 = { };

  test = with lib; {
    name = "appOfApps-custom-default-destination";
    description = "Check the logic of appOfApps destination vs application destinations.";
    assertions = [
      {
        description = "Default destination is applied to the appOfApps.";
        expression = config.applications.__bootstrap.resources.applications.apps.spec;
        assertion = spec: spec.destination.server == defaultServer;
      }
      {
        description = "Default destination is applied to the test application.";
        expression = config.applications.apps.resources.applications.test.spec;
        assertion = spec: spec.destination.server == defaultServer;
      }
    ];
  };
}
