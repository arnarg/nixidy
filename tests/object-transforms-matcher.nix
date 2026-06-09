{ lib, ... }:
let
  inherit (import ../modules/nixidy/transforms.nix { inherit lib; }) selectorToPredicate ruleType;
  res = {
    kind = "Secret";
    apiVersion = "v1";
    metadata.namespace = "argocd";
    metadata.name = "argocd-secret";
    metadata.labels = {
      "app.kubernetes.io/name" = "x";
      "custom" = "y";
    };
  };
  p = sel: selectorToPredicate sel res;
  evalRule =
    match:
    (lib.evalModules {
      modules = [
        {
          options.rule = lib.mkOption { type = ruleType; };
          config.rule = { inherit match; };
        }
      ];
    }).config.rule.predicate;
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
          labels = {
            "app.kubernetes.io/name" = "x";
          };
        };
        expected = true;
      }
      {
        description = "label value mismatch";
        expression = p {
          labels = {
            "app.kubernetes.io/name" = "z";
          };
        };
        expected = false;
      }
      {
        description = "ns + name AND";
        expression = p {
          namespace = "argocd";
          name = "argocd-secret";
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
