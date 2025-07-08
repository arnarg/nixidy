{
  pkgs,
  lib ? pkgs.lib,
}: let
  fromCRD = {
    name,
    src,
    crds,
    namePrefix ? "",
    attrNameOverrides ? {},
  }:
    import ./crd/default.nix {
      inherit pkgs lib name src crds namePrefix attrNameOverrides;
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
