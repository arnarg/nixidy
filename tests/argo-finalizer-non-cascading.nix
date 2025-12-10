{
  lib,
  config,
  ...
}:
{
  # Create an application with everything default.
  applications.test.finalizer = "non-cascading";

  test = with lib; {
    name = "argo-finalizer-non-cascading";
    description = "Validate the finalizer of the application.";
    assertions = [
      {
        description = "The finalizer is set to non-cascading";
        expression = config.applications.apps.resources.applications.test;
        assertion = app: app.metadata.finalizers == null;
      }
    ];
  };
}
