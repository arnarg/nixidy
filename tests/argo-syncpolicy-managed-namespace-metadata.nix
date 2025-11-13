{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  applications = {
    # Create an application without any managedNamespaceMetadata.
    test1 = { };

    # Create an application with managedNamespaceMetadata annotations.
    test2.syncPolicy.managedNamespaceMetadata.annotations = {
      some-annotation = "value";
    };

    # Create an application with managedNamespaceMetadata labels.
    test3.syncPolicy.managedNamespaceMetadata.labels = {
      some-label = "value";
    };
  };

  test = with lib; {
    name = "argo-syncpolicy-managed-namespace-metadata";
    description = "Check that the ArgoCD Application has the correct managedNamespaceMetadata";
    assertions = [
      {
        description = "Application without any managedNamespaceMetadata";
        expression = config.applications.apps.resources.applications.test1.spec.syncPolicy;
        assertion = sp: sp.managedNamespaceMetadata == null && sp.syncOptions == null;
      }
      {
        description = "Application with managedNamespaceMetadata.annotations";
        expression = config.applications.apps.resources.applications.test2.spec.syncPolicy;
        assertion =
          sp:
          sp.managedNamespaceMetadata != null
          && sp.managedNamespaceMetadata.annotations == { some-annotation = "value"; }
          && sp.managedNamespaceMetadata.labels == null
          &&
            (compareLists compare sp.syncOptions [
              "CreateNamespace=true"
            ]) == 0;
      }
      {
        description = "Application with managedNamespaceMetadata.labels";
        expression = config.applications.apps.resources.applications.test3.spec.syncPolicy;
        assertion =
          sp:
          sp.managedNamespaceMetadata != null
          && sp.managedNamespaceMetadata.annotations == null
          && sp.managedNamespaceMetadata.labels == { some-label = "value"; }
          &&
            (compareLists compare sp.syncOptions [
              "CreateNamespace=true"
            ]) == 0;
      }
    ];
  };
}
