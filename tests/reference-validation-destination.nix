{
  lib,
  config,
  ...
}:
let
  failing = lib.filter (a: !a.assertion) config.nixidy.assertions;

  messages = map (a: a.message) failing;
in
{
  nixidy.validation.references.enable = true;

  applications = {
    # Defines a ConfigMap on the local cluster, keyed by `destination.name`.
    definer = {
      namespace = "mixed-ns";
      destination.name = "in-cluster";
      resources.configMaps.mixed-cm.data.X = "1";
    };

    # Same cluster key as the definer, so the definition resolves.
    namesake = {
      namespace = "mixed-ns";
      destination.name = "in-cluster";
      resources.deployments.ok.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v.configMap.name = "mixed-cm";
        };
      };
    };

    # Keeps the default destination (server key,
    # "https://kubernetes.default.svc") is the same cluster in
    # reality, but has a different cluster key, so the definer's
    # ConfigMap does not resolve for it. This false positive is a
    # known limitation, pinned here intentionally.
    referrer = {
      namespace = "mixed-ns";
      resources.deployments.broken.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v.configMap.name = "mixed-cm";
        };
      };
    };
  };

  test = {
    name = "cross-resource reference validation cluster keys";
    description = "Check that definitions are scoped by destination key (name, else server)";
    assertions = [
      {
        description = "only the mixed name/server key mismatch is reported";
        expression = failing;
        assertion = f: builtins.length f == 1;
      }
      {
        description = "the referrer's reference is reported as unresolved";
        expression = messages;
        assertion =
          ms:
          lib.any (
            m:
            lib.hasInfix "application `referrer`: Deployment `mixed-ns/broken` references ConfigMap `mixed-cm`" m
          ) ms;
      }
      {
        description = "the namesake's same-key reference resolves without assertion";
        expression = messages;
        assertion = ms: lib.all (m: !(lib.hasInfix "namesake" m) && !(lib.hasInfix "ok`" m)) ms;
      }
    ];
  };
}
