{
  lib,
  config,
  ...
}: let
  apps = config.applications.${config.nixidy.appOfApps.name};
in {
  # `__` prefix makes an application an
  # internal application
  applications.__test = {
    # Even if you override the name it
    # should use the attribute name to
    # exclude internal applications
    name = "test";
  };

  test = with lib; {
    name = "internal applications";
    description = "Check that applications with the internal application prefix is not a part of appOfApps.";
    assertions = [
      {
        description = "Application `__test` should not be included.";

        expression = hasAttr "__test" apps.resources.applications;

        expected = false;
      }

      {
        description = "App of apps should not have an Application resource for an internal application.";

        expression =
          findFirst
          (x: x.kind == "Application" && x.metadata.name == "test")
          null
          apps.objects;

        expected = null;
      }
    ];
  };
}
