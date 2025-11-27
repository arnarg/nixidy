{
  lib,
  config,
  ...
}:
{
  applications.${config.nixidy.appOfApps.name}.finalizer = "non-cascading";

  # Create an application with everything default.
  applications.test.resources.namespaces.test = { };

  test = with lib; {
    name = "appOfApps-finalizer-non-cascading";
    description = "Validate the finalizer of the appOfApps.";
    assertions = [
      {
        description = "No finalizers listed in the app.";
        expression = config.applications.__bootstrap.resources.applications.apps;
        assertion = app: app.metadata.finalizers == null;
      }
    ];
  };
}
