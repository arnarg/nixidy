{ lib, config, ... }:
lib.mkIf (config.nixidy.presentation.backend == "argocd") {
  # The ArgoCD `Application` CRD type. Conditional on the argocd backend so a
  # flux-only config does not pull it in.
  nixidy.applicationImports = lib.mkIf config.nixidy.baseImports [ ../../generated/argocd.nix ];

  # Per-application argocd options (`applications.<name>.argocd.*`) plus the
  # back-compat aliases for the old top-level paths.
  nixidy.presentation.perAppModules = [
    ./options.nix
    ./aliases.nix
  ];
}
