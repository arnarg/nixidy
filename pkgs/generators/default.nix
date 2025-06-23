{
  pkgs,
  lib ? pkgs.lib,
}: let
  fromSpec = name: spec:
    import ./k8s.nix {
      inherit pkgs lib name spec;
    };

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
      rev = "v3.0.0";
      hash = "sha256-g401mpNEhCNe8H6lk2HToAEZlZa16Py8ozK2z5/UozA=";
    };
    crds = [
      "manifests/crds/application-crd.yaml"
      "manifests/crds/applicationset-crd.yaml"
      "manifests/crds/appproject-crd.yaml"
    ];
  };

  k8s = pkgs.linkFarm "k8s-generated" (
    builtins.attrValues (
      builtins.mapAttrs (version: sha: let
        short = builtins.concatStringsSep "." (lib.lists.sublist 0 2 (builtins.splitVersion version));
      in {
        name = "v${short}.nix";
        path = fromSpec "v${short}" (builtins.fetchurl {
          url = "https://github.com/kubernetes/kubernetes/raw/v${version}/api/openapi-spec/swagger.json";
          sha256 = sha;
        });
      })
      (import ./versions.nix)
    )
  );
}
