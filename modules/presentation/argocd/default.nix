{ lib, config, ... }:
lib.mkIf (config.nixidy.presentation.backend == "argocd") {
  # The ArgoCD `Application` CRD type. Conditional on the argocd backend so a
  # flux-only config does not pull it in.
  nixidy.applicationImports = lib.mkIf config.nixidy.baseImports [ ../../generated/argocd.nix ];
}
