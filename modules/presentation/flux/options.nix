# Per-application Flux options (`applications.<name>.flux.*`), threaded into the
# applications submodule via `nixidy.presentation.perAppModules` when the flux
# backend is selected.
{ lib, ... }:
{
  options.flux = with lib; {
    interval = mkOption {
      type = types.str;
      default = "10m";
      description = "Reconciliation interval for this application's Flux Kustomization.";
    };
    prune = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the Flux Kustomization prunes resources removed from the source.";
    };
    path = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Override the synced path (defaults to the app's output.path).";
    };
  };
}
