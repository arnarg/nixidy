{
  pkgs,
  lib ? pkgs.lib,
}: let
  fromCRD = {
    name,
    src,
    crds,
    # Mapping of CRD definitionKey to attrName
    # Useful to avoid breaking collisions or shorten long type names
    # Ex: {"authenticationflow.keycloak.crossplane.io.v1alpha1.Bindings" = "keycloakBindings";}
    attrNameOverrides ? {},
  }:
    import ./crd.nix {
      inherit pkgs lib name src crds attrNameOverrides;
    };
in {
  inherit fromCRD;

  k8s = import ./k8s {inherit pkgs lib;};

  argocd = fromCRD {
    name = "argocd";
    src = pkgs.fetchFromGitHub {
      owner = "argoproj";
      repo = "argo-cd";
      rev = "v3.0.0";
      hash = "sha256-g401mpNEhCNe8H6lk2HToAEZlZa16Py8ozK2z5/UozA=";
    };
    crds = [
      "manifests/crds/application-crd.yaml"
      "manifests/crds/applicationset-crd.yaml"
      "manifests/crds/appproject-crd.yaml"
    ];
  };
}
