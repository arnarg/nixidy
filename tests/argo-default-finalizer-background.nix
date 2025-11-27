{
  lib,
  config,
  ...
}:
{
  nixidy.defaults.finalizer = "background";

  # Create an application with everything default.
  applications.test.resources.namespaces.test = { };

  test = with lib; {
    name = "argo-default-finalizer-background";
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
