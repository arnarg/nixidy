{
  lib,
  config,
  ...
}:
let
  failing = lib.filter (a: !a.assertion) config.nixidy.assertions;

  activeWarnings = lib.filter (w: w.when) config.nixidy.warnings;

  warningMessage = if activeWarnings == [ ] then "" else (builtins.head activeWarnings).message;
in
{
  nixidy.validation.references.enable = true;
  nixidy.validation.references.severity = "warning";

  applications.miss = {
    namespace = "ns-warn";
    resources.deployments.web.spec = {
      selector = { };
      template.spec = {
        containers.c1 = { };
        volumes.cfg.configMap.name = "foi";
      };
    };
  };

  test = {
    name = "cross-resource reference validation warning severity";
    description = "Check that severity = \"warning\" reports unresolved references as warnings instead of failing assertions";
    assertions = [
      {
        description = "no failing assertions in warning mode";
        expression = failing;
        expected = [ ];
      }
      {
        description = "exactly one active warning";
        expression = activeWarnings;
        assertion = w: builtins.length w == 1;
      }
      {
        description = "warning message contains the missing ConfigMap foi";
        expression = warningMessage;
        assertion = m: lib.hasInfix "foi" m;
      }
    ];
  };
}
