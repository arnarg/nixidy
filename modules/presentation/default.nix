{ lib, ... }:
{
  imports = [ ./argocd ];

  options.nixidy.presentation = with lib; {
    backend = mkOption {
      type = types.enum [
        "argocd"
        "flux"
      ];
      default = "argocd";
      description = "The GitOps presentation backend that synthesizes controller objects (ArgoCD Applications, Flux Kustomizations).";
    };
    perAppModules = mkOption {
      # `raw` (not `applicationImports`' precise oneOf): a backend may contribute
      # any module value (inline attrset, function, alias module), all of which
      # are spliced verbatim into the applications submodule's `modules` list.
      type = with types; listOf raw;
      default = [ ];
      internal = true;
      description = "Per-application option modules contributed by the active presentation backend (threaded into the applications submodule).";
    };
  };
}
