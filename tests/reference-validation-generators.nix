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

    ignore = [
      {
        app = "ignoreapp";
        kind = "PersistentVolumeClaim";
        name = "ignored-pvc";
      }
      {
        app = "ignoreapp";
        kind = "ServiceAccount";
        name = "ignored-sa";
      }
    ];

    # User-extensible generator rule; merged with the built-ins.
    generators.Secret.MyThing.namePath = [
      "spec"
      "secret"
    ];
  };

  applications = {
    # cert-manager Certificate generating a Secret consumed by a workload
    certapp = {
      namespace = "ns-cert";
      yamls = [
        ''
          apiVersion: cert-manager.io/v1
          kind: Certificate
          metadata:
            name: cert1
          spec:
            secretName: tls-secret
        ''
      ];
      resources.deployments.d.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v.secret.secretName = "tls-secret";
        };
      };
    };

    # ExternalSecret without spec.target.name falls back to metadata.name
    esapp = {
      namespace = "ns-es";
      yamls = [
        ''
          apiVersion: external-secrets.io/v1beta1
          kind: ExternalSecret
          metadata:
            name: db-creds
        ''
      ];
      resources.deployments.d.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v.secret.secretName = "db-creds";
        };
      };
    };

    # user-defined generator rule (MyThing -> Secret via spec.secret)
    customgen = {
      namespace = "ns-cg";
      yamls = [
        ''
          apiVersion: example.com/v1
          kind: MyThing
          metadata:
            name: thing1
          spec:
            secret: gen-secret
        ''
      ];
      resources.deployments.d.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v.secret.secretName = "gen-secret";
        };
      };
    };

    # ServiceAccounts: built-in "default" exception, defined SA, missing SA
    saapp = {
      namespace = "ns-sa";
      yamls = [
        ''
          apiVersion: v1
          kind: ServiceAccount
          metadata:
            name: my-sa
        ''
      ];
      resources.deployments = {
        usesDefault.spec = {
          selector = { };
          template.spec = {
            containers.c1 = { };
            serviceAccountName = "default";
          };
        };
        usesDefined.spec = {
          selector = { };
          template.spec = {
            containers.c1 = { };
            serviceAccountName = "my-sa";
          };
        };
        usesMissing.spec = {
          selector = { };
          template.spec = {
            containers.c1 = { };
            serviceAccountName = "missing-sa";
          };
        };
      };
    };

    # StatefulSet volumeClaimTemplates define PVCs; unknown PVC still fails
    stsapp = {
      namespace = "ns-sts";
      yamls = [
        ''
          apiVersion: apps/v1
          kind: StatefulSet
          metadata:
            name: sts1
          spec:
            selector:
              matchLabels:
                app: sts1
            volumeClaimTemplates:
              - metadata:
                  name: sts-data
            template:
              metadata:
                labels:
                  app: sts1
              spec:
                containers:
                  - name: c1
                volumes:
                  - name: v
                    persistentVolumeClaim:
                      claimName: sts-data
        ''
      ];
      resources.deployments.d.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          volumes.v.persistentVolumeClaim.claimName = "other-pvc";
        };
      };
    };

    # ignore rules scoped to PVC and ServiceAccount kinds
    ignoreapp = {
      namespace = "ns-ig";
      resources.deployments.d.spec = {
        selector = { };
        template.spec = {
          containers.c1 = { };
          serviceAccountName = "ignored-sa";
          volumes.v.persistentVolumeClaim.claimName = "ignored-pvc";
        };
      };
    };
  };

  test = {
    name = "cross-resource reference validation of PVCs, ServiceAccounts and generators";
    description = "Check PVC/ServiceAccount references and CRD generator rules";
    assertions = [
      {
        description = "one failing validation assertion per unresolved reference";
        expression = failing;
        assertion = f: builtins.length f == 2;
      }
      {
        description = "missing ServiceAccount reported with its path";
        expression = messages;
        assertion =
          ms:
          lib.any (
            m: lib.hasInfix "ServiceAccount `missing-sa` (spec.template.spec.serviceAccountName)" m
          ) ms;
      }
      {
        description = "missing PVC reported with its path";
        expression = messages;
        assertion =
          ms:
          lib.any (
            m:
            lib.hasInfix "PersistentVolumeClaim `other-pvc` (spec.template.spec.volumes[0].persistentVolumeClaim.claimName)" m
          ) ms;
      }
      {
        description = "generator-generated Secrets resolve";
        expression = messages;
        assertion =
          ms:
          lib.all (
            m:
            !(lib.hasInfix "tls-secret" m)
            && !(lib.hasInfix "db-creds" m)
            && !(lib.hasInfix "gen-secret" m)
            && !(lib.hasInfix "sts-data" m)
          ) ms;
      }
      {
        description = "built-in default ServiceAccount and ignore rules do not fail";
        expression = messages;
        assertion = ms: lib.all (m: !(lib.hasInfix "ignored-pvc" m) && !(lib.hasInfix "ignored-sa" m)) ms;
      }
    ];
  };
}
