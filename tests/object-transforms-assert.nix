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
  applications = {
    good = {
      namespace = "test";
      objectTransforms.foo = {
        replace = res: res;
      };
    };

    bad = {
      namespace = "test";
      objectTransforms.double-action = {
        replace = res: res;
        update = { };
      };
    };

    bad-nested-transform = {
      namespace = "test";
      objectTransforms.outer = {
        transforms.inner = {
          replace = res: res;
          update = { };
        };
      };
    };
  };

  nixidy.objectTransforms.foo = {
    replace = res: res;
    transforms.foo.update = { };
  };

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
        description = "A bad nested transform has a failing XOR assertion";
        expression = apps.bad-nested-transform.assertions;
        assertion = as: lib.any (a: !a.assertion && lib.hasInfix "outer.inner" a.message) as;
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
