{
  lib,
  config,
  ...
}: let
  apps = config.applications.apps.resources.applications;
  hasAnnotation = name: value: annotations: (lib.hasAttr name annotations) && annotations.${name} == value;
in {
  applications = {
    # Create an application with all compare options set
    test1.compareOptions = {
      ignoreExtraneous = true;
      includeMutationWebhook = true;
      serverSideDiff = true;
    };

    # Create an application with one compare option set
    test2.compareOptions = {
      serverSideDiff = true;
    };

    # Create an application with no compare option set
    test3 = {};
  };

  test = {
    name = "compare options";
    description = "Check that compare options are set correctly.";
    assertions = [
      {
        description = "Application with all compare options should set them correctly.";
        expression = apps.test1.metadata.annotations;
        assertion = hasAnnotation "argocd.argoproj.io/compare-options" "IgnoreExtraneous,IncludeMutationWebhook=true,ServerSideDiff=true";
      }

      {
        description = "Application with one compare option should set it correctly.";
        expression = apps.test2.metadata.annotations;
        assertion = hasAnnotation "argocd.argoproj.io/compare-options" "ServerSideDiff=true";
      }

      {
        description = "Application with no compare option should set it correctly.";
        expression = apps.test3.metadata.annotations;
        assertion = isNull;
      }
    ];
  };
}
