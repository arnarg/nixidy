{ lib, ... }:
let
  inherit (import ../modules/nixidy/transforms.nix { inherit lib; }) partSelectorToPredicate;
  res = {
    kind = "Pod";
    apiVersion = "v1";
    metadata = {
      namespace = "argocd";
      name = "a-pod";
      labels = {
        "app.kubernetes.io/name" = "x";
        "custom" = "y";
      };
    };
    spec.containers = [
      { envFrom = [{ secretRef.name = "a"; }]; }
      { envFrom = [{ secretRef.name = "b"; }]; }
    ];
  };
  p = sel: partSelectorToPredicate sel res;
in
{
  test = {
    name = "objectTransforms part matcher";
    description = "partSelectorToPredicate ANDs fields; ORs lists";
    assertions = [
      {
        description = "kind match";
        expression = p { kind = "Pod"; };
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
          metadata.namespace = "argocd";
          metadata.name = "a-pod";
        };
        expected = true;
      }
      {
        description = "match list element";
        expression = p {
          spec.containers.envFrom.secretRef.name = "a";
        };
        expected = true;
      }
      {
        description = "false when no list element matches";
        expression = p {
          spec.containers.envFrom.secretRef.name = "c";
        };
        expected = false;
      }
      {
        description = "match any value in a list";
        expression = p {
          spec.containers.envFrom.secretRef.name = [ "a" "c" ];
        };
        expected = true;
      }
      {
        description = "false when no items match";
        expression = p {
          spec.containers.envFrom.secretRef.name = [ "c" "d" ];
        };
        expected = false;
      }
      {
        description = "top-level list";
        expression = p [
          { spec.containers.envFrom.secretRef.name = [ "a" ]; }
          { spec.containers.envFrom.secretRef.name = [ "b" ]; }
        ];
        expected = true;
      }
    ];
  };
}
