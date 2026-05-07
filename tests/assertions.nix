{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  applications.test1 = {
    namespace = "test";
    resources.configMaps.cm.data.FOO = "bar";
  };

  applications.test2 = {
    namespace = "test";
    resources.configMaps.cm.data.BAZ = "qux";
    assertions = [
      {
        assertion = lib.length apps.test2.objects > 0;
        message = "test2 should have at least one object";
      }
    ];
    warnings = [ "test2 warning example" ];
  };

  nixidy.assertions = [
    {
      assertion = apps ? test1;
      message = "test1 application must exist";
    }
    {
      assertion = lib.length apps.test1.objects == 1;
      message = "test1 should have exactly one object";
    }
  ];

  nixidy.warnings = [ "global warning example" ];

  test = {
    name = "assertions and warnings";
    description = "Check that per-app and global assertions and warnings work";
    assertions = [
      {
        description = "test1 has one assertion available";
        expression = builtins.length apps.test1.assertions;
        expected = 0;
      }
      {
        description = "test2 has one assertion that passes";
        expression = apps.test2.assertions;
        assertion = as: builtins.length as == 1 && (builtins.head as).assertion;
      }
      {
        description = "test2 has one warning";
        expression = apps.test2.warnings;
        expected = [
          {
            when = true;
            message = "test2 warning example";
            context = "test2";
          }
        ];
      }
      {
        description = "nixidy has two global assertions";
        expression = builtins.length config.nixidy.assertions;
        expected = 2;
      }
      {
        description = "nixidy has one global warning";
        expression = config.nixidy.warnings;
        expected = [
          {
            when = true;
            message = "global warning example";
            context = "global";
          }
        ];
      }
    ];
  };
}
