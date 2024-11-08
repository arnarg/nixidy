{
  pkgs,
  kubelib,
}: let
  lib = import ./default.nix {inherit pkgs kubelib;};
in {
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
        expr = lib.kube.removeLabels ["helm.sh/chart"] {
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
        expr = lib.kube.removeLabels ["helm.sh/chart"] {
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
        expr = lib.kube.removeLabels ["helm.sh/chart"] {
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
        expr = lib.kube.removeLabels ["helm.sh/chart"] {
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
        expr = lib.kube.removeLabels ["helm.sh/chart"] {
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
    };
  };
}
