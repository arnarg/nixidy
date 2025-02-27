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
      rev = "v2.14.2";
      hash = "sha256-HiKTJ6X8py/mIcU+jSRonvYBxQMZ6Onzmu0/SorvPKg=";
    };
    crds = [
      "manifests/crds/application-crd.yaml"
      "manifests/crds/applicationset-crd.yaml"
      "manifests/crds/appproject-crd.yaml"
    ];
  };
}
