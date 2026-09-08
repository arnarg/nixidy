{ lib, ... }:
let
  inherit (import ../modules/nixidy/transforms.nix { inherit lib; })
    selectorToPredicate
    mkObjectTransformsOption
    ;
  res = {
    kind = "Secret";
    apiVersion = "v1";
    metadata = {
      namespace = "argocd";
      name = "argocd-secret";
      labels = {
        "app.kubernetes.io/name" = "x";
        "custom" = "y";
      };
    };
  };
  p = sel: selectorToPredicate sel res;
  evalRule =
    match:
    (lib.evalModules {
      modules = [
        {
          options.rule = mkObjectTransformsOption "";
          config.rule.foo = { inherit match; };
        }
      ];
    }).config.rule.foo.predicate;
in
{
  test = {
    name = "objectTransforms matcher";
    description = "selectorToPredicate ANDs fields; labels/annotations subset";
    assertions = [
      {
        description = "kind match";
        expression = p { kind = "Secret"; };
        expected = true;
      }
      {
        description = "kind mismatch";
        expression = p { kind = "ConfigMap"; };
        expected = false;
      }
      {
        description = "absent fields ignored (match all)";
        expression = p { };
        expected = true;
      }
      {
        description = "label subset matches";
        expression = p {
          metadata.labels = {
            "app.kubernetes.io/name" = "x";
          };
        };
        expected = true;
      }
      {
        description = "label value mismatch";
        expression = p {
          metadata.labels = {
            "app.kubernetes.io/name" = "z";
          };
        };
        expected = false;
      }
      {
        description = "ns + name AND";
        expression = p {
          metadata = {
            namespace = "argocd";
            name = "argocd-secret";
          };
        };
        expected = true;
      }
      {
        description = "predicate resolves declarative selector match";
        expression = (evalRule { kind = "Secret"; }) res;
        expected = true;
      }
      {
        description = "predicate resolves declarative selector mismatch";
        expression = (evalRule { kind = "ConfigMap"; }) res;
        expected = false;
      }
      {
        description = "predicate uses predicate-fn form directly";
        expression = (evalRule (r: r.kind == "Secret")) res;
        expected = true;
      }
    ];
  };
}
