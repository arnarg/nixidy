{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  # Create an application with a helm chart
  # and overriding the values and using a
  # transformer
  applications.test1.helm.releases.test1 = {
    chart = ./chart;
    values = {
      replicaCount = 3;
      image.tag = "1.0.0";
      service.port = 8080;
      issuer.create = true;
    };
  };

  test = with lib; {
    name = "helm chart with values overrides";
    description = "Create an application with Helm chart without setting values.";
    assertions = [
      {
        description = "Deployment should be rendered correctly.";

        expression = findFirst (
          x: x.kind == "Deployment" && x.metadata.name == "test1-chart"
        ) null apps.test1.objects;

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
            replicas = 3;
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
        description = "Service should be rendered correctly.";

        expression = findFirst (
          x: x.kind == "Service" && x.metadata.name == "test1-chart"
        ) null apps.test1.objects;

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
                port = 8080;
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
        description = "Issuer should be included and rendered correctly.";

        expression = lib.findFirst (
          x: x.kind == "Issuer" && x.metadata.name == "ca-issuer"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "cert-manager.io/v1";
          kind = "Issuer";
          metadata = {
            name = "ca-issuer";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "app.kubernetes.io/version" = "1.16.0";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec.ca.secretName = "ca-key-pair";
        };
      }

      {
        description = "Job hook should be rendered correctly.";

        expression = findFirst (
          x: x.kind == "Job" && x.metadata.name == "job-hook"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "batch/v1";
          kind = "Job";
          metadata = {
            name = "job-hook";
            namespace = "test1";
            annotations = {
              "helm.sh/hook" = "post-install,post-upgrade";
            };
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "app.kubernetes.io/version" = "1.16.0";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec = {
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
                  name = "chart-job-hook";
                  image = "busybox";
                  command = [
                    "sh"
                    "-c"
                    "echo The hook Job is running"
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
