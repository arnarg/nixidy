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
        rewrite = res: res;
      }
    ];
  };

  applications.bad = {
    namespace = "test";
    objectTransforms = [
      {
        name = "double-action";
        rewrite = res: res;
        postProcess.command = "cat";
      }
    ];
  };

  nixidy.objectTransforms = [
    {
      rewrite = res: res;
      postProcess.command = "cat";
    }
  ];

  test = {
    name = "objectTransforms XOR assertion";
    description = "objectTransforms rules must set exactly one of rewrite/postProcess at env + app scope";
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
        description = "the failing message names the offending rule";
        expression = apps.bad.assertions;
        assertion = as: lib.any (a: !a.assertion && lib.hasInfix "double-action" a.message) as;
      }
      {
        description = "env has a failing XOR assertion";
        expression = config.nixidy.assertions;
        assertion = as: lib.any mentionsXor as;
      }
    ];
  };
}
