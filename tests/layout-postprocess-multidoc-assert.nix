{ lib, config, ... }:
{
  applications.multidoc = {
    namespace = "test";
    yamls = [
      ''
        apiVersion: example.com/v1
        kind: Widget
        metadata:
          name: shared
          namespace: alpha
        ---
        apiVersion: example.com/v1
        kind: Widget
        metadata:
          name: shared
          namespace: zeta
      ''
    ];
    objectTransforms = [
      {
        match.namespace = "alpha";
        postProcess = "cat";
      } # matches only the alpha doc
    ];
  };

  test = {
    name = "layout multi-doc postProcess assertion";
    description = "post-processing one object in a multi-object group fails the strengthened assertion";
    assertions = [
      {
        description = "a failing assertion names the offending app and path";
        expression = config.nixidy.assertions;
        assertion =
          as:
          lib.any (
            a: !a.assertion && lib.hasInfix "multidoc" a.message && lib.hasInfix "Widget-shared.yaml" a.message
          ) as;
      }
    ];
  };
}
