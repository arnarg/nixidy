{ config, ... }:
let
  apps = config.applications;
in
{
  applications.test1 = {
    name = "test1override";
  };

  test = {
    name = "application name override";
    description = "Check that application name override works as expected.";
    assertions = [
      {
        description = "Output path should use override name.";

        expression = apps.test1.output.path;

        expected = "test1override";
      }

      {
        description = "Namespace without override should use override name.";

        expression = apps.test1.namespace;

        expected = "test1override";
      }

      {
        description = "Generated Argo CD applicaiton should use override name.";

        expression = apps.apps.resources.applications.test1.metadata.name;

        expected = "test1override";
      }
    ];
  };
}
