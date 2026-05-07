{
  modules,
  pkgs,
  kubelib,
  lib ? pkgs.lib,
  extraSpecialArgs ? { },
  libOverlay ? null,
}:
let
  extendedLib = import ../lib { inherit pkgs kubelib; };

  nixidyModules = import ./modules.nix;

  module = lib.evalModules {
    modules = modules ++ [ ./templates.nix ] ++ nixidyModules;
    specialArgs = {
      inherit pkgs;
      lib = if builtins.isFunction libOverlay then extendedLib.extend libOverlay else extendedLib;
    }
    // extraSpecialArgs;
  };

  allAssertions =
    module.config.nixidy.assertions
    ++ lib.concatMap (name: module.config.applications.${name}.assertions) (
      builtins.attrNames module.config.applications
    );

  failed = lib.filter (a: !a.assertion) allAssertions;

  formatFailed =
    assertions:
    "failed assertions:\n"
    + (lib.concatMapStringsSep "\n" (a: "- assertion(${a.context}): ${a.message}") assertions);

  allWarnings = lib.filter (warning: warning.when) (
    module.config.nixidy.warnings
    ++ lib.concatMap (name: module.config.applications.${name}.warnings) (
      builtins.attrNames module.config.applications
    )
  );

  traceIfWarnings =
    ret:
    if allWarnings != [ ] then
      builtins.trace (
        "warnings:\n"
        + (lib.concatMapStringsSep "\n" (w: "- warning(${w.context}): ${w.message}") allWarnings)
      ) ret
    else
      ret;
in
lib.throwIf (failed != [ ]) (formatFailed failed) (traceIfWarnings {
  inherit (module) config;
  inherit (module.config.build)
    environmentPackage
    activationPackage
    bootstrapPackage
    declarativePackage
    ;
  meta = { inherit (module.config.nixidy.target) repository branch; };
})
