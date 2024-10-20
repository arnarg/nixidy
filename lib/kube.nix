{
  lib,
  klib,
  ...
}: {
  /*
  Parses a YAML document string into a list of attribute sets.

  > This is re-exported directly from [farcaller/nix-kube-generators](https://github.com/farcaller/nix-kube-generators).

  Type:
    fromYAML :: String -> [AttrSet]

  Example:
    fromYAML ''
      apiVersion: v1
      kind: Namespace
      metadata:
        name: default
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: kube-system
    ''
    => [
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = "default";
      }
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = "kube-system";
      }
    ]
  */
  fromYAML =
    # String with a yaml document.
    yaml:
      klib.fromYAML yaml;

  /*
  Parse an octal representation of a number and convert into a decimal number. This can be useful when having to represent permission bits in a resource as nix has no support for representing octal numbers.

  Type:
    fromOctal :: String -> Integer

  Example:
    fromOctal "0555"
    => 365
  */
  fromOctal =
    # String representation of the octal number to parse.
    octal: let
      noPrefix = lib.strings.removePrefix "0o" octal;
      parsed = builtins.fromTOML "v=0o${noPrefix}";
    in
      parsed.v;

  /*
  Removes labels from a Kubernetes manifest.

  Type:
    removeLabels :: [String] -> AttrSet -> AttrSet

  Example:
    removeLabels ["helm.sh/chart"] {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "argocd-cm";
        labels = {
          "app.kubernetes.io/name" = "argocd-cm";
          "helm.sh/chart" = "argo-cd-5.51.6";
        };
      };
    }
    => {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "argocd-cm";
        labels = {
          "app.kubernetes.io/name" = "argocd-cm";
        };
      };
    }
  */
  removeLabels =
    # List of labels that should be removed
    labels:
    # Kubernetes manifest
    manifest:
      manifest
      // {
        metadata =
          manifest.metadata
          // (
            if manifest.metadata ? labels
            then {
              labels = removeAttrs manifest.metadata.labels labels;
            }
            else {}
          );
      };
}
