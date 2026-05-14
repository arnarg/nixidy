{
  lib,
  config,
  ...
}:
let
  apps = config.applications.apps.resources.applications;
in
{
  applications = {
    # Application with labels
    test1.labels = {
      "app.kubernetes.io/name" = "test1";
      "environment" = "dev";
    };

    # Application with empty labels
    test2.labels = { };

    # Application with no labels (uses default)
    test3 = { };
  };

  test = {
    name = "application labels";
    description = "Check that labels are correctly added to ArgoCD Applications";
    assertions = [
      {
        description = "Application should have labels set correctly.";
        expression = apps.test1.metadata.labels;
        assertion =
          labels:
          labels == {
            "app.kubernetes.io/name" = "test1";
            "environment" = "dev";
          };
      }

      {
        description = "Application with empty labels should be null in output.";
        expression = apps.test2.metadata.labels;
        assertion = labels: labels == null;
      }

      {
        description = "Application with no labels should be null in output.";
        expression = apps.test3.metadata.labels;
        assertion = labels: labels == null;
      }
    ];
  };
}
