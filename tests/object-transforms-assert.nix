{
  lib,
  config,
  ...
}:
let
  apps = config.applications;

  mentionsXor = a: !a.assertion && lib.hasInfix "exactly one" a.message;
in
{
  applications.good = {
    namespace = "test";
    objectTransforms = [
      {
        map = res: res;
      }
    ];
  };

  applications.bad = {
    namespace = "test";
    objectTransforms = [
      {
        map = res: res;
        render.command = "cat";
      }
    ];
  };

  nixidy.objectTransforms = [
    {
      map = res: res;
      render.command = "cat";
    }
  ];

  test = {
    name = "objectTransforms XOR assertion";
    description = "objectTransforms rules must set exactly one of map/render at env + app scope";
    assertions = [
      {
        description = "good app assertion passes";
        expression = apps.good.assertions;
        assertion = as: lib.length as == 1 && (lib.head as).assertion;
      }
      {
        description = "bad app has a failing XOR assertion";
        expression = apps.bad.assertions;
        assertion = as: lib.any mentionsXor as;
      }
      {
        description = "env has a failing XOR assertion";
        expression = config.nixidy.assertions;
        assertion = as: lib.any mentionsXor as;
      }
    ];
  };
}
