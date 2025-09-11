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
    test1.resources.configMaps.cm.data = {
      "FOO" = "bar";
      "_BAZ" = "qux";
    };
  };

  test = with lib; {
    name = "configmap data fields";
    description = "Check if configmap data fields are properly handled";
    assertions = [
      {
        description = "Application `test1` configmap data should include '_BAZ'";

        expression = elemAt apps.test1.objects 0;

        assertion = cm: builtins.hasAttr "_BAZ" cm.data;
      }
    ];
  };
}
