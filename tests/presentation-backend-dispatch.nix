# Presentation dispatch: selecting an unregistered backend surfaces a friendly
# `nixidy.assertions` entry (assertion = false) rather than a raw eval error.
# The module-test harness (modules/testing/eval.nix) never invokes the production
# `throwIf` gate, so we assert on `config.nixidy.assertions` directly — the same
# seam tests/assertions.nix exercises.
{ lib, config, ... }:
let
  unknown = lib.filter (
    a: !a.assertion && a.message == "unknown presentation backend `nope`; known backends: argocd, flux."
  ) config.nixidy.assertions;
in
{
  nixidy.presentation.backend = "nope";

  test = {
    name = "presentation backend dispatch";
    description = "an unregistered presentation backend produces a failing nixidy.assertions entry with a friendly message";
    assertions = [
      {
        description = "exactly one unknown-backend assertion is present, false, with the listed known backends";
        expression = unknown;
        assertion = us: lib.length us == 1;
      }
    ];
  };
}
