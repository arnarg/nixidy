{
  lib,
  config,
  ...
}:
let
  customProject = "custom-project";
in
{
  nixidy.appOfApps = {
    # Set the app-of-apps project
    project = customProject;
  };

  # Create an application with everything default.
  applications.test.resources.namespaces.test1 = { };

  test = with lib; {
    name = "appOfApps-custom-project";
    description = "Check the application of correct project to the appOfApps.";
    assertions = [
      {
        description = "Custom project is applied to the bootstrap manifest.";
        expression = config.applications.__bootstrap.resources.applications.apps.spec;
        assertion = spec: spec.project == customProject;
      }
    ];
  };
}
