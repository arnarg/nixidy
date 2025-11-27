{
  lib,
  config,
  ...
}:
{
  # Create an application with everything default.
  applications.test.finalizer = "background";

  test = with lib; {
    name = "argo-finalizer-background";
    description = "Validate the finalizer of the application.";
    assertions = [
      {
        description = "The finalizer is set to background";
        expression = config.applications.apps.resources.applications.test;
        assertion = app: app.metadata.finalizers == [ "resources-finalizer.argocd.argoproj.io/background" ];
      }
    ];
  };
}
