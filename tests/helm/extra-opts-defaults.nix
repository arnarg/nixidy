{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  nixidy.defaults.helm.extraOpts = [ "--api-versions=monitoring.coreos.com/v1" ];

  # Create an application with a helm chart.
  applications.test1.helm.releases.test1 = {
    chart = ./chart;
  };

  test = with lib; {
    name = "helm chart with defaults extra opts";
    description = "Create an application with Helm chart and default extra opts.";
    assertions = [
      {
        description = "ServiceMonitor should be rendered correctly.";

        expression = findFirst (
          x: x.kind == "ServiceMonitor" && x.metadata.name == "test1-chart"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "monitoring.coreos.com/v1";
          kind = "ServiceMonitor";
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
            selector.matchLabels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/name" = "chart";
            };
            namespaceSelector.matchNames = [ "test1" ];
            endpoints = [
              {
                port = "http";
                path = "/metrics";
                interval = "30s";
                scrapeTimeout = "10s";
              }
            ];
          };
        };
      }
    ];
  };
}
