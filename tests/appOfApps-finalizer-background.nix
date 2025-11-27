{
  lib,
  config,
  ...
}:
{
  applications.${config.nixidy.appOfApps.name}.finalizer = "background";

  # Create an application with everything default.
  applications.test.resources.namespaces.test = { };

  test = with lib; {
    name = "appOfApps-finalizer-background";
    description = "Validate the finalizer of the appOfApps.";
    assertions = [
      {
        description = "The finalizer is set to background";
        expression = config.applications.__bootstrap.resources.applications.apps;
        assertion = app: app.metadata.finalizers == [ "resources-finalizer.argocd.argoproj.io/background" ];
      }
    ];
  };
}
