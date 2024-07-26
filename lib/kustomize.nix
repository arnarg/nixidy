{
  lib,
  pkgs,
  ...
}: {
  /*
  Builds a kustomization and creates a derivation with the output.

  Type:
    buildKustomization :: AttrSet -> Derivation

  Example:
    buildKustomization {
      name = "argocd";
      src = pkgs.fetchFromGitHub {
        owner = "argoproj";
        repo = "argo-cd";
        rev = "v2.9.3";
        hash = "sha256-GaY4Cw/LlSwy35umbB4epXt6ev8ya19UjHRwhDwilqU=";
      };
      path = "manifests/cluster-install";
      namespace = "argocd";
    }
    => /nix/store/7i52...7pww-kustomize-argocd
  */
  buildKustomization = {
    # Name is only used for derivation name.
    name,
    # Derivation containing the kustomization entrypoint and
    # all relative bases that it might reference.
    src,
    # Relative path from the base of `src` to the kustomization
    # folder to render.
    path,
    # Override namespace in kustomization.yaml.
    namespace ? null,
  }: let
    sanitizedPath = lib.removePrefix "/" path;
  in
    pkgs.stdenv.mkDerivation {
      inherit src;
      name = "kustomize-${name}";

      phases = ["unpackPhase" "patchPhase" "installPhase"];

      patchPhase = lib.optionalString (!builtins.isNull namespace) ''
        ${pkgs.yq-go}/bin/yq -i '.namespace = "${namespace}"' "${sanitizedPath}/kustomization.yaml"
      '';

      installPhase = ''
        ${pkgs.kubectl}/bin/kubectl kustomize "${sanitizedPath}" -o "$out"
      '';
    };
}
