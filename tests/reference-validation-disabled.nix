{
  lib,
  config,
  ...
}:
let
  failing = lib.filter (a: !a.assertion) config.nixidy.assertions;
in
{
  nixidy.validation.enable = false;

  applications.miss = {
    namespace = "ns-a";
    resources.deployments.web.spec.template.spec.volumes.cfg.configMap.name = "foi";
  };

  test = {
    name = "cross-resource reference validation disabled";
    description = "Check that validation can be turned off";
    assertions = [
      {
        description = "no failing assertions when validation is disabled";
        expression = failing;
        expected = [ ];
      }
    ];
  };
}
