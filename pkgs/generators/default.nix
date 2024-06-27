{
  pkgs,
  lib ? pkgs.lib,
}: let
  fromCRD = {
    name,
    src,
    crds,
  }:
    import ./crd.nix {
      inherit pkgs lib name src crds;
    };
in {
  inherit fromCRD;

  argocd = fromCRD {
    name = "argocd";
    src = pkgs.fetchFromGitHub {
      owner = "argoproj";
      repo = "argo-cd";
      rev = "v2.11.3";
      hash = "sha256-qSrMqByhOitRltYaVjIeubuoTR74x/pQ1Ad+uTPdpJU=";
    };
    crds = [
      "manifests/crds/application-crd.yaml"
      "manifests/crds/appproject-crd.yaml"
    ];
  };
}
