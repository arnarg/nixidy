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

      {
        description = "Layout is keyed by the attr key, not the override name.";

        expression = builtins.attrNames (
          builtins.intersectAttrs {
            test1 = null;
            test1override = null;
          } config.build.layout
        );

        expected = [ "test1" ];
      }

      {
        description = "Environment package renders an app whose name is overridden.";

        # Forcing drvPath instantiates every app's render derivation, which is
        # the path that looked the layout up by the (overridable) app name.
        expression = builtins.isString config.build.environmentPackage.drvPath;

        expected = true;
      }
    ];
  };
}
