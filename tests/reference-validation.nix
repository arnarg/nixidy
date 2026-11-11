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

  nixidy.validation.references.ignore = [
    {
      app = "excl";
      kind = "Secret";
      name = "leak-secret";
    }
    {
      name = "other.missing";
    }
    {
      name = "dyn-*";
    }
    # Addresses the app-key vs app-name identifier: `overridden` is the
    # attribute key; the app's configured name is `renamed-app`.
    {
      app = "overridden";
      kind = "Secret";
      name = "ovr-secret";
    }
  ];

  # --- app with missing references (volumes + env + internal-cm) ---
  applications = {
    miss = {
      namespace = "ns-a";
      resources.deployments.web.spec = {
        selector = { };
        template.spec = {
          volumes.cfg.configMap.name = "foi";
          containers.c1.env = {
            FOO.valueFrom.secretKeyRef = {
              name = "gone";
              key = "K";
            };
            BAR.valueFrom.secretKeyRef = {
              name = "gone";
              key = "K";
            };
            BAZ.valueFrom.secretKeyRef = {
              name = "gone";
              key = "K";
            };
            INTERNAL.valueFrom.configMapKeyRef = {
              name = "internal-cm";
              key = "K";
            };
          };
        };
      };
    };

    # --- app where everything resolves ---
    ok = {
      namespace = "ns-ok";
      resources = {
        configMaps.ok-cm.data.FOO = "1";
        secrets.pull-s.stringData.X = "y";
        deployments.good.spec = {
          selector = { };
          template.spec = {
            volumes = {
              v1.configMap.name = "ok-cm";
              v2.secret.secretName = "pull-s";
              v3.projected.sources = [
                { configMap.name = "ok-cm"; }
                { secret.name = "pull-s"; }
              ];
            };
            containers.c1 = {
              envFrom = [
                { configMapRef.name = "ok-cm"; }
                { secretRef.name = "pull-s"; }
              ];
              env = {
                V1.valueFrom.configMapKeyRef = {
                  name = "ok-cm";
                  key = "K";
                };
                V2.valueFrom.secretKeyRef = {
                  name = "pull-s";
                  key = "K";
                };
              };
            };
            initContainers.ic.envFrom = [ { secretRef.name = "pull-s"; } ];
            imagePullSecrets = [ { name = "pull-s"; } ];
          };
        };
      };
    };

    # --- opaque yamls-defined ConfigMap referenced by a typed workload ---
    opaque = {
      namespace = "ns-op";
      yamls = [
        ''
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: yaml-cm
          data:
            FOO: "1"
        ''
      ];
      resources.deployments.d.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v1.configMap.name = "yaml-cm";
        };
      };
    };

    # --- cross-application same-namespace reference ---
    xa = {
      namespace = "shared";
      resources.deployments.d.spec = {
        selector = { };
        template.spec.containers.c1.env.V.valueFrom.configMapKeyRef = {
          name = "shared-cm";
          key = "K";
        };
      };
    };
    xb = {
      namespace = "shared";
      resources.configMaps.shared-cm.data.X = "1";
    };

    # --- CronJob path ---
    cron = {
      namespace = "ns-cron";
      resources.cronJobs.job.spec = {
        schedule = "*/5 * * * *";
        jobTemplate.spec.template.spec.containers.c1.env.X.valueFrom.configMapKeyRef = {
          name = "cron-cm";
          key = "X";
        };
      };
    };

    # --- Pod path ---
    podapp = {
      namespace = "ns-pod";
      resources.pods.p1.spec.containers.c1.env.Y.valueFrom.secretKeyRef = {
        name = "pod-secret";
        key = "K";
      };
    };

    # --- exclusions: three suppressed, one still failing ---
    excl = {
      namespace = "ns-e";
      resources.deployments.d.spec = {
        selector = { };
        template.spec.containers.c1.env = {
          S.valueFrom.secretKeyRef = {
            name = "leak-secret";
            key = "K";
          };
          C.valueFrom.configMapKeyRef = {
            name = "other.missing";
            key = "K";
          };
          G.valueFrom.secretKeyRef = {
            name = "dyn-other";
            key = "K";
          };
          S2.valueFrom.configMapKeyRef = {
            name = "still-missing";
            key = "K";
          };
        };
      };
    };

    # app-scoped exclusion must not leak to other apps
    excl2 = {
      namespace = "ns-e2";
      resources.deployments.d.spec = {
        selector = { };
        template.spec.containers.c1.env.S.valueFrom.secretKeyRef = {
          name = "leak-secret";
          key = "K";
        };
      };
    };

    # --- multi-cluster: same namespace, different destination clusters ---
    # app on remote cluster A references missing `clusterA-cm` while an app
    # on cluster B defines a ConfigMap with the same name/namespace —
    # destination scoping must prevent a false pass.
    mcA = {
      namespace = "mc-shared";
      destination.server = "https://cluster-a.example.com";
      resources.deployments.d.spec = {
        selector = { };
        template.spec.containers.c1.env.V.valueFrom.configMapKeyRef = {
          name = "clusterA-cm";
          key = "K";
        };
      };
    };
    mcB = {
      namespace = "mc-shared";
      destination.server = "https://cluster-b.example.com";
      resources.configMaps.clusterA-cm.data.X = "1";
    };

    # --- ephemeralContainers path ---
    eph = {
      namespace = "ns-eph";
      resources.pods.p1.spec = {
        containers.c1 = { };
        ephemeralContainers.e1.env.DBG.valueFrom.configMapKeyRef = {
          name = "eph-cm";
          key = "K";
        };
      };
    };

    # --- exclusion matching uses the app's configured name, not its key ---
    overridden = {
      name = "renamed-app";
      namespace = "ns-ovr";
      resources.deployments.d.spec = {
        selector = { };
        template.spec.containers.c1.env.S.valueFrom.secretKeyRef = {
          name = "ovr-secret";
          key = "K";
        };
      };
    };

    # --- internal application: neither satisfies nor triggers validation ---
    __tmpl = {
      namespace = "ns-t";
      resources = {
        configMaps.internal-cm.data.X = "y";
        deployments.t.spec = {
          selector = { };
          template.spec.containers.c1.env.X.valueFrom.configMapKeyRef = {
            name = "tmpl-cm";
            key = "K";
          };
        };
      };
    };
  };

  test = {
    name = "cross-resource reference validation";
    description = "Check that workload ConfigMap/Secret references resolve against environment definitions";
    assertions = [
      {
        description = "one failing validation assertion per unresolved reference";
        expression = failing;
        assertion = f: builtins.length f == 11;
      }
      {
        description = "a message contains the missing ConfigMap foi";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "foi" m) ms;
      }
      {
        description = "repeated secret refs are reported once per reference site";
        expression = messages;
        assertion = ms: lib.length (lib.filter (m: lib.hasInfix "gone" m) ms) == 3;
      }
      {
        description = "internal app definitions do not satisfy public refs";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "internal-cm" m) ms;
      }
      {
        description = "cronjob reference checked";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "cron-cm" m) ms;
      }
      {
        description = "pod reference checked";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "pod-secret" m) ms;
      }
      {
        description = "app-scoped exclusion does not leak to other apps";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "excl2" m && lib.hasInfix "leak-secret" m) ms;
      }
      {
        description = "non-excluded ref in exclusion app still fails";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "still-missing" m) ms;
      }
      {
        description = "valid refs do not appear in any message";
        expression = messages;
        assertion =
          ms:
          lib.all (
            m: !(lib.hasInfix "ok-cm" m) && !(lib.hasInfix "yaml-cm" m) && !(lib.hasInfix "shared-cm" m)
          ) ms;
      }
      {
        description = "excluded refs do not appear in any message";
        expression = messages;
        assertion =
          ms:
          lib.all (
            m: !(lib.hasInfix "other.missing" m) && !(lib.hasInfix "dyn-other" m) && !(lib.hasInfix "tmpl-cm" m)
          ) ms;
      }
      {
        description = "messages carry the per-application prefix";
        expression = messages;
        assertion =
          ms: lib.any (m: lib.hasInfix "application `miss`: Deployment `ns-a/web` references ConfigMap" m) ms;
      }
      {
        description = "same-namespace ref on a different destination cluster still fails";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "clusterA-cm" m && lib.hasInfix "mcA" m) ms;
      }
      {
        description = "same-namespace definition on another cluster does not leak (no cross-cluster resolution)";
        expression = messages;
        assertion = ms: lib.all (m: !(lib.hasInfix "mcB" m)) ms;
      }
      {
        description = "ephemeralContainers references are checked";
        expression = messages;
        assertion = ms: lib.any (m: lib.hasInfix "eph-cm" m && lib.hasInfix "Pod `ns-eph/p1`" m) ms;
      }
      {
        description = "exclusion scoped by attribute key applies even when app name is overridden";
        expression = messages;
        assertion = ms: lib.all (m: !(lib.hasInfix "ovr-secret" m)) ms;
      }
    ];
  };
}
