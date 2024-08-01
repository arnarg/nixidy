{
  lib,
  config,
  ...
}: let
  apps = config.applications;
in {
  applications = {
    # Create an application with `createNamespace = true`
    test1.createNamespace = true;

    # Create an application with `createNamespace = false`
    test2.createNamespace = false;
  };

  test = {
    name = "create namespace";
    description = "Check that a namespace gets created when createNamespace is specified.";
    assertions = [
      {
        description = "A namespace resource should be created when `createNamespace = true`.";
        expression = apps.test1.resources.namespaces.test1;
        assertion = ns:
          ns.kind
          == "Namespace"
          && ns.metadata.name == "test1";
      }

      {
        description = "A namespace resource should not be created when `createNamespace = false`.";
        expression = apps.test2.resources.namespaces;
        assertion = nss: !(lib.hasAttr "test2" nss);
      }
    ];
  };
}
