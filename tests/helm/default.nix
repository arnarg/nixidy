{
  lib,
  config,
  ...
}: let
  apps = config.applications;
in {
  applications = {
    # Create an application with a helm chart
    test1.helm.releases.test1 = {
      chart = ./chart;
    };

    # Create an application with a helm chart
    # and overriding the values and using a
    # transformer
    test2.helm.releases.test2 = {
      chart = ./chart;
      values = {
        replicaCount = 3;
        image.tag = "1.0.0";
        service.port = 8080;
        issuer.create = true;
      };

      transformer = map (lib.kube.removeLabels [
        "app.kubernetes.io/version"
        "helm.sh/chart"
      ]);
    };

    # Create an application with a helm chart
    # and resource override
    test3 = {
      helm.releases.test3 = {
        chart = ./chart;
      };

      resources.deployments.test3-chart.spec.template.spec.containers.chart.image = lib.mkForce "nginx:2.0.0";
    };
  };

  test = with lib; {
    name = "helm charts";
    description = "Check that helm charts are rendered correctly.";
    assertions = [
      {
        description = "Helm chart with no values override should render deployment correctly.";
        expression =
          findFirst
          (x: x.kind == "Deployment" && x.metadata.name == "test1-chart")
          null
          apps.test1.objects;
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
              "app.kubernetes.io/version" = "1.16.0";
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
                "app.kubernetes.io/version" = "1.16.0";
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
      }

      {
        description = "Helm chart with no values override should render service correctly.";
        expression =
          findFirst
          (x: x.kind == "Service" && x.metadata.name == "test1-chart")
          null
          apps.test1.objects;
        expected = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "app.kubernetes.io/version" = "1.16.0";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec = {
            type = "ClusterIP";
            ports = [
              {
                port = 80;
                targetPort = "http";
                protocol = "TCP";
                name = "http";
              }
            ];
            selector = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/name" = "chart";
            };
          };
        };
      }

      {
        description = "Helm chart with values override should render deployment correctly.";
        expression =
          findFirst
          (x: x.kind == "Deployment" && x.metadata.name == "test2-chart")
          null
          apps.test2.objects;
        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "test2-chart";
            namespace = "test2";
            labels = {
              "app.kubernetes.io/instance" = "test2";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            };
          };
          spec = {
            replicas = 3;
            selector.matchLabels = {
              "app.kubernetes.io/instance" = "test2";
              "app.kubernetes.io/name" = "chart";
            };
            template = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test2";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
                "app.kubernetes.io/version" = "1.16.0";
                "helm.sh/chart" = "chart-0.1.0";
              };
              spec.containers = [
                {
                  name = "chart";
                  image = "nginx:1.0.0";
                  ports = [
                    {
                      name = "http";
                      containerPort = 8080;
                      protocol = "TCP";
                    }
                  ];
                }
              ];
            };
          };
        };
      }

      {
        description = "Helm chart with values override should render service correctly.";
        expression =
          findFirst
          (x: x.kind == "Service" && x.metadata.name == "test2-chart")
          null
          apps.test2.objects;
        expected = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "test2-chart";
            namespace = "test2";
            labels = {
              "app.kubernetes.io/instance" = "test2";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            };
          };
          spec = {
            type = "ClusterIP";
            ports = [
              {
                port = 8080;
                targetPort = "http";
                protocol = "TCP";
                name = "http";
              }
            ];
            selector = {
              "app.kubernetes.io/instance" = "test2";
              "app.kubernetes.io/name" = "chart";
            };
          };
        };
      }

      {
        description = "Helm chart with unsupported resource types should still output the resource.";
        expression =
          lib.findFirst
          (x: x.kind == "Issuer" && x.metadata.name == "ca-issuer")
          null
          apps.test2.objects;
        expected = {
          apiVersion = "cert-manager.io/v1";
          kind = "Issuer";
          metadata = {
            name = "ca-issuer";
            labels = {
              "app.kubernetes.io/instance" = "test2";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            };
          };
          spec.ca.secretName = "ca-key-pair";
        };
      }

      {
        description = "Resource override in nixidy should override resource rendered by helm.";
        expression =
          findFirst
          (x: x.kind == "Deployment" && x.metadata.name == "test3-chart")
          null
          apps.test3.objects;
        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "test3-chart";
            namespace = "test3";
            labels = {
              "app.kubernetes.io/instance" = "test3";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "app.kubernetes.io/version" = "1.16.0";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels = {
              "app.kubernetes.io/instance" = "test3";
              "app.kubernetes.io/name" = "chart";
            };
            template = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test3";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
                "app.kubernetes.io/version" = "1.16.0";
                "helm.sh/chart" = "chart-0.1.0";
              };
              spec.containers = [
                {
                  name = "chart";
                  image = "nginx:2.0.0";
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
      }
    ];
  };
}
