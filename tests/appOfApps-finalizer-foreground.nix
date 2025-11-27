{
  lib,
  config,
  ...
}:
{
  applications.${config.nixidy.appOfApps.name}.finalizer = "foreground";

  # Create an application with everything default.
  applications.test.resources.namespaces.test = { };

  test = with lib; {
    name = "appOfApps-finalizer-foreground";
    description = "Validate the finalizer of the appOfApps.";
    assertions = [
      {
        description = "The finalizer is set to foreground";
        expression = config.applications.__bootstrap.resources.applications.apps;
        assertion = app: app.metadata.finalizers == [ "resources-finalizer.argocd.argoproj.io" ];
      }
    ];
  };
}
