{
  lib,
  config,
  ...
}:
{
  # Create an application with everything default.
  applications.test.finalizer = "foreground";

  test = with lib; {
    name = "argo-finalizer-foreground";
    description = "Validate the finalizer of the application.";
    assertions = [
      {
        description = "The finalizer is set to foreground";
        expression = config.applications.apps.resources.applications.test;
        assertion = app: app.metadata.finalizers == [ "resources-finalizer.argocd.argoproj.io" ];
      }
    ];
  };
}
