{
  lib,
  config,
  ...
}:
{
  applications = {
    # Create an application that does not override
    # any defaults
    test1.resources.namespaces.test1 = { };

    # Create an applicaton that sets the server
    test2 = {
      destination.server = "https://localhost:6443";
    };

    # Create an applicaton that sets the name
    test3 = {
      destination.name = "in-cluster";
    };
  };

  test = with lib; {
    name = "destination";
    description = "Check that destination get set on all generated applications.";
    assertions = [
      {
        description = "Applications with no overrides gets the default server";
        expression = config.applications.apps.resources.applications.test1.spec;
        assertion =
          spec: spec.destination.name == null && spec.destination.server == "https://kubernetes.default.svc";
      }
      {
        description = "Applications with custom server gets the correct server";
        expression = config.applications.apps.resources.applications.test2.spec;
        assertion =
          spec: spec.destination.name == null && spec.destination.server == "https://localhost:6443";
      }
      {
        description = "Applications with name gets the name without server";
        expression = config.applications.apps.resources.applications.test3.spec;
        assertion = spec: spec.destination.name == "in-cluster" && spec.destination.server == null;
      }
    ];
  };
}
