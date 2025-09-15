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
    # Create an application with `createNamespace = true`
    test1.createNamespace = true;

    # Create an application with `createNamespace = false`
    test2.createNamespace = false;
  };

  test = with lib; {
    name = "create namespace";
    description = "Check that a namespace gets created when createNamespace is specified.";
    assertions = [
      {
        description = "A namespace resource should be created when `createNamespace = true`.";

        expression = findFirst (
          x: x.kind == "Namespace" && x.metadata.name == "test1"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "v1";
          kind = "Namespace";
          metadata.name = "test1";
        };
      }

      {
        description = "A namespace resource should not be created when `createNamespace = false`.";

        expression = findFirst (x: x.kind == "Namespace") null apps.test2.objects;

        assertion = isNull;
      }
    ];
  };
}
