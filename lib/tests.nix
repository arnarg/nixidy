{
  pkgs,
  kubelib,
}:
let
  lib = import ./default.nix { inherit pkgs kubelib; };

  app =
    {
      name ? "app",
      namespace ? "ns",
      cluster ? "",
    }:
    {
      inherit name namespace cluster;
      key = name;
      objects = [ ];
    };
in
{
  kube = {
    fromYAML = {
      testSingleObject = {
        expr = lib.kube.fromYAML ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: default
        '';
        expected = [
          {
            apiVersion = "v1";
            kind = "Namespace";
            metadata.name = "default";
          }
        ];
      };
      testMultipleObjects = {
        expr = lib.kube.fromYAML ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: default
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: kube-system
        '';
        expected = [
          {
            apiVersion = "v1";
            kind = "Namespace";
            metadata.name = "default";
          }
          {
            apiVersion = "v1";
            kind = "Namespace";
            metadata.name = "kube-system";
          }
        ];
      };
    };

    fromOctal = {
      testConvertToCorrectInteger = {
        expr = lib.kube.fromOctal "0555";
        expected = 365;
      };
      testWithOctalPrefix = {
        expr = lib.kube.fromOctal "0o555";
        expected = 365;
      };
    };

    removeLabels = {
      testLabelPresent = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
              "helm.sh/chart" = "argo-cd-5.51.6";
            };
          };
        };
        expected = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
            };
          };
        };
      };
      testLabelAbsent = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
              "app" = "argocd";
            };
          };
        };
        expected = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
              "app" = "argocd";
            };
          };
        };
      };
      testNoLabels = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "argocd";
          };
        };
        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "argocd";
          };
        };
      };
      testSpecialTemplateLabels = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/name" = "chart";
            };
            template = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
                "helm.sh/chart" = "chart-0.1.0";
              };
              spec.containers = [
                {
                  name = "chart";
                  image = "nginx:latest";
                  ports = [
                    {
                      name = "http";
                      containerPort = 80;
                      protocol = "TCP";
                    }
                  ];
                }
              ];
            };
          };
        };
        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/name" = "chart";
            };
            template = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
              };
              spec.containers = [
                {
                  name = "chart";
                  image = "nginx:latest";
                  ports = [
                    {
                      name = "http";
                      containerPort = 80;
                      protocol = "TCP";
                    }
                  ];
                }
              ];
            };
          };
        };
      };
      testCronJobTemplateLabels = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "batch/v1";
          kind = "CronJob";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec = {
            schedule = "*/20 * * * *";
            jobTemplate = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
                "helm.sh/chart" = "chart-0.1.0";
              };
              spec.template = {
                metadata.labels = {
                  "app.kubernetes.io/instance" = "test1";
                  "app.kubernetes.io/managed-by" = "Helm";
                  "app.kubernetes.io/name" = "chart";
                  "helm.sh/chart" = "chart-0.1.0";
                };
                spec.containers = [
                  {
                    name = "chart";
                    image = "nginx:latest";
                    ports = [
                      {
                        name = "http";
                        containerPort = 80;
                        protocol = "TCP";
                      }
                    ];
                  }
                ];
              };
            };
          };
        };
        expected = {
          apiVersion = "batch/v1";
          kind = "CronJob";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            };
          };
          spec = {
            schedule = "*/20 * * * *";
            jobTemplate = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
              };
              spec.template = {
                metadata.labels = {
                  "app.kubernetes.io/instance" = "test1";
                  "app.kubernetes.io/managed-by" = "Helm";
                  "app.kubernetes.io/name" = "chart";
                };
                spec.containers = [
                  {
                    name = "chart";
                    image = "nginx:latest";
                    ports = [
                      {
                        name = "http";
                        containerPort = 80;
                        protocol = "TCP";
                      }
                    ];
                  }
                ];
              };
            };
          };
        };
      };
    }
    // (builtins.listToAttrs (
      map
        (kind: {
          name = "test${kind}MatchLabels";
          value = {
            expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
              apiVersion = "apps/v1";
              inherit kind;
              metadata = {
                name = "test-${lib.toLower kind}";
                labels = {
                  "app.kubernetes.io/name" = "test";
                  "helm.sh/chart" = "test-chart";
                };
              };
              spec = {
                replicas = 1;
                selector.matchLabels = {
                  "app.kubernetes.io/name" = "test";
                  "helm.sh/chart" = "test-chart";
                };
              };
            };
            expected = {
              apiVersion = "apps/v1";
              inherit kind;
              metadata = {
                name = "test-${lib.toLower kind}";
                labels = {
                  "app.kubernetes.io/name" = "test";
                };
              };
              spec = {
                replicas = 1;
                selector.matchLabels = {
                  "app.kubernetes.io/name" = "test";
                };
              };
            };
          };
        })
        [
          "DaemonSet"
          "Deployment"
          "ReplicaSet"
          "StatefulSet"
        ]
    ));
  };

  validation = {
    globMatches = {
      testExact = {
        expr = lib.validation.globMatches "foo-bar" "foo-bar";
        expected = true;
      };
      testLiteralDotDoesNotMatchOtherChar = {
        expr = lib.validation.globMatches "foo.bar" "fooXbar";
        expected = false;
      };
      testLiteralDotMatchesDot = {
        expr = lib.validation.globMatches "foo.bar" "foo.bar";
        expected = true;
      };
      testTrailingWildcard = {
        expr = lib.validation.globMatches "dyn-*" "dyn-secret";
        expected = true;
      };
      testTrailingWildcardNoMatch = {
        expr = lib.validation.globMatches "dyn-*" "other";
        expected = false;
      };
    };

    effectiveNamespace = {
      testFallbackWhenMissing = {
        expr = lib.validation.effectiveNamespace (app { namespace = "a"; }) { };
        expected = "a";
      };
      testFallbackWhenNull = {
        expr = lib.validation.effectiveNamespace (app { namespace = "a"; }) {
          metadata.namespace = null;
        };
        expected = "a";
      };
      testFallbackWhenEmpty = {
        expr = lib.validation.effectiveNamespace (app { namespace = "a"; }) {
          metadata.namespace = "";
        };
        expected = "a";
      };
      testExplicitNamespace = {
        expr = lib.validation.effectiveNamespace (app { namespace = "a"; }) {
          metadata.namespace = "b";
        };
        expected = "b";
      };
    };

    refsFromPodSpec = {
      testVolumesAndContainers = {
        expr = lib.validation.refsFromPodSpec "spec" {
          volumes = [
            { configMap.name = "cm-vol"; }
            {
              secret.secretName = "sec-vol";
              secret.optional = true;
            }
            {
              projected.sources = [
                { configMap.name = "cm-proj"; }
                { secret.name = "sec-proj"; }
              ];
            }
          ];
          containers = [
            {
              envFrom = [
                { configMapRef.name = "cm-envfrom"; }
                { secretRef.name = "sec-envfrom"; }
              ];
              env = [
                {
                  name = "A";
                  valueFrom.configMapKeyRef = {
                    name = "cm-key";
                    key = "K";
                  };
                }
                {
                  name = "B";
                  valueFrom.secretKeyRef = {
                    name = "sec-key";
                    key = "K";
                  };
                }
              ];
            }
          ];
          imagePullSecrets = [ { name = "pull"; } ];
        };
        expected = [
          {
            kind = "ConfigMap";
            name = "cm-vol";
            optional = false;
            path = "spec.volumes[0].configMap.name";
          }
          {
            kind = "Secret";
            name = "sec-vol";
            optional = true;
            path = "spec.volumes[1].secret.secretName";
          }
          {
            kind = "ConfigMap";
            name = "cm-proj";
            optional = false;
            path = "spec.volumes[2].projected.sources[0].configMap.name";
          }
          {
            kind = "Secret";
            name = "sec-proj";
            optional = false;
            path = "spec.volumes[2].projected.sources[1].secret.name";
          }
          {
            kind = "ConfigMap";
            name = "cm-envfrom";
            optional = false;
            path = "spec.containers[0].envFrom[0].configMapRef.name";
          }
          {
            kind = "Secret";
            name = "sec-envfrom";
            optional = false;
            path = "spec.containers[0].envFrom[1].secretRef.name";
          }
          {
            kind = "ConfigMap";
            name = "cm-key";
            optional = false;
            path = "spec.containers[0].env[0].valueFrom.configMapKeyRef.name";
          }
          {
            kind = "Secret";
            name = "sec-key";
            optional = false;
            path = "spec.containers[0].env[1].valueFrom.secretKeyRef.name";
          }
          {
            kind = "Secret";
            name = "pull";
            optional = false;
            path = "spec.imagePullSecrets[0].name";
          }
        ];
      };

      testImagePullSecretsInvalidEntriesSkipped = {
        expr = lib.validation.refsFromPodSpec "spec" {
          containers = [ { } ];
          imagePullSecrets = [
            { }
            { name = null; }
            { name = ""; }
            { name = "pull"; }
          ];
        };
        expected = [
          {
            kind = "Secret";
            name = "pull";
            optional = false;
            path = "spec.imagePullSecrets[3].name";
          }
        ];
      };

      testPvcVolumeAndServiceAccount = {
        expr = lib.validation.refsFromPodSpec "spec" {
          volumes = [ { persistentVolumeClaim.claimName = "data"; } ];
          serviceAccountName = "my-sa";
          containers = [ { } ];
        };
        expected = [
          {
            kind = "PersistentVolumeClaim";
            name = "data";
            optional = false;
            path = "spec.volumes[0].persistentVolumeClaim.claimName";
          }
          {
            kind = "ServiceAccount";
            name = "my-sa";
            optional = false;
            path = "spec.serviceAccountName";
          }
        ];
      };

      testDefaultServiceAccountSkipped = {
        expr = lib.validation.refsFromPodSpec "spec" {
          serviceAccountName = "default";
          containers = [ { } ];
        };
        expected = [ ];
      };

      testSystemNamesSkipped = {
        expr = lib.validation.refsFromPodSpec "spec" {
          volumes = [ { configMap.name = "kube-root-ca.crt"; } ];
          containers = [ { } ];
        };
        expected = [ ];
      };

      testNonStringAndEmptyNamesSkipped = {
        expr = lib.validation.refsFromPodSpec "spec" {
          volumes = [
            { configMap.name = 42; }
            { configMap.name = ""; }
          ];
          containers = [ { } ];
        };
        expected = [ ];
      };

      testAllContainerClassesWalked = {
        expr = lib.validation.refsFromPodSpec "spec" {
          containers = [ { envFrom = [ { secretRef.name = "c"; } ]; } ];
          initContainers = [ { envFrom = [ { secretRef.name = "i"; } ]; } ];
          ephemeralContainers = [ { envFrom = [ { secretRef.name = "e"; } ]; } ];
        };
        expected = [
          {
            kind = "Secret";
            name = "c";
            optional = false;
            path = "spec.containers[0].envFrom[0].secretRef.name";
          }
          {
            kind = "Secret";
            name = "i";
            optional = false;
            path = "spec.initContainers[0].envFrom[0].secretRef.name";
          }
          {
            kind = "Secret";
            name = "e";
            optional = false;
            path = "spec.ephemeralContainers[0].envFrom[0].secretRef.name";
          }
        ];
      };

      testCronJobPrefix = {
        expr = lib.validation.objectRefs (app { }) {
          kind = "CronJob";
          metadata.name = "job";
          spec.jobTemplate.spec.template.spec.containers = [
            {
              env = [
                {
                  name = "X";
                  valueFrom.configMapKeyRef = {
                    name = "cron-cm";
                    key = "X";
                  };
                }
              ];
            }
          ];
        };
        expected = [
          {
            app = "app";
            appKey = "app";
            workloadKind = "CronJob";
            workloadName = "job";
            kind = "ConfigMap";
            name = "cron-cm";
            path = "spec.jobTemplate.spec.template.spec.containers[0].env[0].valueFrom.configMapKeyRef.name";
            ns = "ns";
            cluster = "";
          }
        ];
      };
    };

    objectRefs = {
      testNullMetadataNameFallsBackToGenerateName = {
        expr = lib.validation.objectRefs (app { }) {
          kind = "Pod";
          metadata = {
            name = null;
            generateName = "gen-";
          };
          spec.containers = [
            {
              env = [
                {
                  name = "Y";
                  valueFrom.configMapKeyRef = {
                    name = "cm";
                    key = "K";
                  };
                }
              ];
            }
          ];
        };
        expected = [
          {
            app = "app";
            appKey = "app";
            workloadKind = "Pod";
            workloadName = "gen-";
            kind = "ConfigMap";
            name = "cm";
            path = "spec.containers[0].env[0].valueFrom.configMapKeyRef.name";
            ns = "ns";
            cluster = "";
          }
        ];
      };

      testNullMetadataNameFallsBackToUnnamed = {
        expr = lib.validation.objectRefs (app { }) {
          kind = "Pod";
          metadata = {
            name = null;
            generateName = null;
          };
          spec.containers = [
            {
              env = [
                {
                  name = "Y";
                  valueFrom.configMapKeyRef = {
                    name = "cm";
                    key = "K";
                  };
                }
              ];
            }
          ];
        };
        expected = [
          {
            app = "app";
            appKey = "app";
            workloadKind = "Pod";
            workloadName = "<unnamed>";
            kind = "ConfigMap";
            name = "cm";
            path = "spec.containers[0].env[0].valueFrom.configMapKeyRef.name";
            ns = "ns";
            cluster = "";
          }
        ];
      };

      testNonWorkloadKindIgnored = {
        expr = lib.validation.objectRefs (app { }) {
          kind = "Service";
          metadata.name = "svc";
        };
        expected = [ ];
      };

      testOptionalSkipped = {
        expr = lib.validation.objectRefs (app { }) {
          kind = "Deployment";
          metadata.name = "web";
          spec.template.spec.containers = [
            {
              env = [
                {
                  name = "A";
                  valueFrom.secretKeyRef = {
                    name = "opt";
                    key = "K";
                    optional = true;
                  };
                }
              ];
            }
          ];
        };
        expected = [ ];
      };

      testMultipleRefsToSameSecretNotDeduplicated = {
        expr = lib.validation.objectRefs (app { }) {
          kind = "Deployment";
          metadata.name = "web";
          spec.template.spec.containers = [
            {
              env = [
                {
                  name = "A";
                  valueFrom.secretKeyRef = {
                    name = "gone";
                    key = "K";
                  };
                }
                {
                  name = "B";
                  valueFrom.secretKeyRef = {
                    name = "gone";
                    key = "K";
                  };
                }
              ];
            }
          ];
        };
        expected = [
          {
            app = "app";
            appKey = "app";
            workloadKind = "Deployment";
            workloadName = "web";
            kind = "Secret";
            name = "gone";
            path = "spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name";
            ns = "ns";
            cluster = "";
          }
          {
            app = "app";
            appKey = "app";
            workloadKind = "Deployment";
            workloadName = "web";
            kind = "Secret";
            name = "gone";
            path = "spec.template.spec.containers[0].env[1].valueFrom.secretKeyRef.name";
            ns = "ns";
            cluster = "";
          }
        ];
      };

      testPodPathAndMetadata = {
        expr =
          lib.validation.objectRefs
            (app {
              name = "web";
              namespace = "demo";
              cluster = "c1";
            })
            {
              kind = "Pod";
              metadata.name = "p1";
              spec.containers = [
                {
                  env = [
                    {
                      name = "Y";
                      valueFrom.configMapKeyRef = {
                        name = "cm";
                        key = "K";
                      };
                    }
                  ];
                }
              ];
            };
        expected = [
          {
            app = "web";
            appKey = "web";
            workloadKind = "Pod";
            workloadName = "p1";
            kind = "ConfigMap";
            name = "cm";
            path = "spec.containers[0].env[0].valueFrom.configMapKeyRef.name";
            ns = "demo";
            cluster = "c1";
          }
        ];
      };
    };

    checkReferences = {
      testMissingReported = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (
              app {
                name = "a";
                namespace = "ns";
              }
              // {
                objects = [
                  {
                    kind = "Deployment";
                    metadata.name = "d";
                    spec.template.spec.volumes = [ { configMap.name = "missing"; } ];
                  }
                ];
              }
            )
          ];
        };
        expected = [
          {
            app = "a";
            appKey = "a";
            workloadKind = "Deployment";
            workloadName = "d";
            kind = "ConfigMap";
            name = "missing";
            path = "spec.template.spec.volumes[0].configMap.name";
            ns = "ns";
            cluster = "";
          }
        ];
      };

      testCrossAppResolve = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (
              app {
                name = "a";
                namespace = "shared";
              }
              // {
                objects = [
                  {
                    kind = "Deployment";
                    metadata.name = "d";
                    spec.template.spec.volumes = [ { configMap.name = "cm"; } ];
                  }
                ];
              }
            )
            (
              app {
                name = "b";
                namespace = "shared";
              }
              // {
                objects = [
                  {
                    kind = "ConfigMap";
                    metadata.name = "cm";
                  }
                ];
              }
            )
          ];
        };
        expected = [ ];
      };

      testClusterIsolation = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (
              app {
                name = "a";
                namespace = "shared";
                cluster = "c1";
              }
              // {
                objects = [
                  {
                    kind = "Deployment";
                    metadata.name = "d";
                    spec.template.spec.volumes = [ { configMap.name = "cm"; } ];
                  }
                ];
              }
            )
            (
              app {
                name = "b";
                namespace = "shared";
                cluster = "c2";
              }
              // {
                objects = [
                  {
                    kind = "ConfigMap";
                    metadata.name = "cm";
                  }
                ];
              }
            )
          ];
        };
        expected = [
          {
            app = "a";
            appKey = "a";
            workloadKind = "Deployment";
            workloadName = "d";
            kind = "ConfigMap";
            name = "cm";
            path = "spec.template.spec.volumes[0].configMap.name";
            ns = "shared";
            cluster = "c1";
          }
        ];
      };

      testNullDefinitionNameDoesNotCrashOrSatisfy = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (
              app {
                name = "a";
                namespace = "ns";
              }
              // {
                objects = [
                  {
                    kind = "Secret";
                    metadata.name = null;
                  }
                  {
                    kind = "Deployment";
                    metadata.name = "d";
                    spec.template.spec.volumes = [ { secret.secretName = "s"; } ];
                  }
                ];
              }
            )
          ];
        };
        expected = [
          {
            app = "a";
            appKey = "a";
            workloadKind = "Deployment";
            workloadName = "d";
            kind = "Secret";
            name = "s";
            path = "spec.template.spec.volumes[0].secret.secretName";
            ns = "ns";
            cluster = "";
          }
        ];
      };

      testVolumeClaimTemplatesDefinePvc = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (app {
              name = "a";
              namespace = "ns";
            } // {
              objects = [
                {
                  kind = "StatefulSet";
                  metadata.name = "sts";
                  spec = {
                    volumeClaimTemplates = [ { metadata.name = "sts-data"; } ];
                    template.spec.volumes = [ { persistentVolumeClaim.claimName = "sts-data"; } ];
                  };
                }
                {
                  kind = "Deployment";
                  metadata.name = "d";
                  spec.template.spec.volumes = [ { persistentVolumeClaim.claimName = "other-pvc"; } ];
                }
              ];
            })
          ];
        };
        expected = [
          {
            app = "a";
            appKey = "a";
            workloadKind = "Deployment";
            workloadName = "d";
            kind = "PersistentVolumeClaim";
            name = "other-pvc";
            path = "spec.template.spec.volumes[0].persistentVolumeClaim.claimName";
            ns = "ns";
            cluster = "";
          }
        ];
      };

      testIgnorePvcAndServiceAccountKinds = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (app {
              name = "a";
              namespace = "ns";
            } // {
              objects = [
                {
                  kind = "Deployment";
                  metadata.name = "d";
                  spec.template.spec = {
                    serviceAccountName = "ignored-sa";
                    volumes = [ { persistentVolumeClaim.claimName = "ignored-pvc"; } ];
                  };
                }
              ];
            })
          ];
          ignore = [
            {
              app = null;
              kind = "ServiceAccount";
              name = "ignored-sa";
            }
            {
              app = null;
              kind = "PersistentVolumeClaim";
              name = "*";
            }
          ];
        };
        expected = [ ];
      };

      testIgnoreRules = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (
              app {
                name = "a";
                namespace = "ns";
              }
              // {
                objects = [
                  {
                    kind = "Deployment";
                    metadata.name = "d";
                    spec.template.spec = {
                      volumes = [ { secret.secretName = "dyn-1"; } ];
                      containers = [ { envFrom = [ { secretRef.name = "dyn-2"; } ]; } ];
                      initContainers = [ { envFrom = [ { secretRef.name = "keep"; } ]; } ];
                    };
                  }
                ];
              }
            )
          ];
          ignore = [
            {
              app = null;
              kind = "Secret";
              name = "dyn-*";
            }
          ];
        };
        expected = [
          {
            app = "a";
            appKey = "a";
            workloadKind = "Deployment";
            workloadName = "d";
            kind = "Secret";
            name = "keep";
            path = "spec.template.spec.initContainers[0].envFrom[0].secretRef.name";
            ns = "ns";
            cluster = "";
          }
        ];
      };

      testIgnoreAppScopedByKey = {
        expr = lib.validation.checkReferences {
          appsObjs = [
            (
              (app {
                name = "renamed";
                namespace = "ns";
              })
              // {
                key = "overridden";
                objects = [
                  {
                    kind = "Deployment";
                    metadata.name = "d";
                    spec.template.spec.volumes = [ { secret.secretName = "s"; } ];
                  }
                ];
              }
            )
          ];
          ignore = [
            {
              app = "overridden";
              kind = null;
              name = "s";
            }
          ];
        };
        expected = [ ];
      };
    };
  };
}
