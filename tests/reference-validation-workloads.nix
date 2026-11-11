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
  nixidy.validation.references = {
    enable = true;

    # User-extensible workload table; merged with the built-in pod-spec kinds.
    workloads.Rollout.podSpecPath = [
      "spec"
      "template"
      "spec"
    ];
  };

  applications = {
    # Argo Rollout (CRD) referencing a missing ConfigMap; its pod spec is
    # walked because its kind is registered above.
    rolloutapp = {
      namespace = "ns-roll";
      yamls = [
        ''
          apiVersion: argoproj.io/v1alpha1
          kind: Rollout
          metadata:
            name: r1
          spec:
            template:
              spec:
                volumes:
                  - name: cfg
                    configMap:
                      name: missing-rollout-cm
                containers:
                  - name: c1
        ''
      ];
    };

    # A custom kind NOT registered in workloads is not walked; its missing
    # reference must not produce an assertion.
    customapp = {
      namespace = "ns-custom";
      yamls = [
        ''
          apiVersion: example.com/v1
          kind: MyJob
          metadata:
            name: j1
          spec:
            template:
              spec:
                volumes:
                  - name: cfg
                    configMap:
                      name: missing-myjob-cm
                containers:
                  - name: c1
        ''
      ];
    };

    # Built-in kinds keep working alongside the extension.
    deployapp = {
      namespace = "ns-dep";
      resources.deployments.d.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v.configMap.name = "missing-deploy-cm";
        };
      };
    };
  };

  test = {
    name = "cross-resource reference validation with custom workload kinds";
    description = "Check that the user-extensible workloads option walks CRD pod specs";
    assertions = [
      {
        description = "one failing validation assertion per unresolved reference";
        expression = failing;
        assertion = f: builtins.length f == 2;
      }
      {
        description = "Rollout reference reported at its podSpecPath";
        expression = messages;
        assertion =
          ms:
          lib.any (
            m:
            lib.hasInfix "Rollout `ns-roll/r1` references ConfigMap `missing-rollout-cm` (spec.template.spec.volumes[0].configMap.name)" m
          ) ms;
      }
      {
        description = "built-in Deployment kind still walked";
        expression = messages;
        assertion =
          ms: lib.any (m: lib.hasInfix "Deployment `ns-dep/d` references ConfigMap `missing-deploy-cm`" m) ms;
      }
      {
        description = "unregistered custom kind is not walked";
        expression = messages;
        assertion = ms: lib.all (m: !(lib.hasInfix "MyJob" m) && !(lib.hasInfix "missing-myjob-cm" m)) ms;
      }
    ];
  };
}
