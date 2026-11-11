{
  lib,
  config,
  ...
}:
let
  failing = lib.filter (a: !a.assertion) config.nixidy.assertions;
in
{
  applications.miss = {
    namespace = "ns-a";
    resources.deployments.web.spec = {
      selector = { };
      template.spec = {
        containers.c1 = { };
        volumes.cfg.configMap.name = "foi";
      };
    };
  };

  test = {
    name = "cross-resource reference validation disabled";
    description = "Check that validation is disabled by default";
    assertions = [
      {
        description = "no failing assertions when validation is disabled";
        expression = failing;
        expected = [ ];
      }
    ];
  };
}
