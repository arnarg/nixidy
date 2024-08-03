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
  };

  test = with lib; {
    name = "helm charts";
    description = "Check that helm charts are rendered correctly.";
    assertions = [
      {
        description = "Helm chart with no values override should render deployment correctly.";
        expression = apps.test1.resources.apps.v1.Deployment.test1-chart;
        assertion = depl: let
          container = head depl.spec.template.spec.containers;
        in
          depl.kind
          == "Deployment"
          && depl.metadata.name == "test1-chart"
          && depl.metadata.namespace == "test1"
          && depl.metadata.labels
          == {
            "app.kubernetes.io/instance" = "test1";
            "app.kubernetes.io/managed-by" = "Helm";
            "app.kubernetes.io/name" = "chart";
            "app.kubernetes.io/version" = "1.16.0";
            "helm.sh/chart" = "chart-0.1.0";
          }
          && depl.spec.replicas == 1
          && container.name == "chart"
          && container.image == "nginx:latest";
      }

      {
        description = "Helm chart with no values override should render service correctly.";
        expression = apps.test1.resources.core.v1.Service.test1-chart;
        assertion = svc: let
          port = head svc.spec.ports;
        in
          svc.kind
          == "Service"
          && svc.metadata.name == "test1-chart"
          && svc.metadata.namespace == "test1"
          && svc.metadata.labels
          == {
            "app.kubernetes.io/instance" = "test1";
            "app.kubernetes.io/managed-by" = "Helm";
            "app.kubernetes.io/name" = "chart";
            "app.kubernetes.io/version" = "1.16.0";
            "helm.sh/chart" = "chart-0.1.0";
          }
          && svc.spec.type == "ClusterIP"
          && port.port == 80
          && port.targetPort == "http"
          && port.protocol == "TCP"
          && port.name == "http";
      }

      {
        description = "Helm chart with values override should render deployment correctly.";
        expression = apps.test2.resources.apps.v1.Deployment.test2-chart;
        assertion = depl: let
          container = head depl.spec.template.spec.containers;
        in
          depl.kind
          == "Deployment"
          && depl.metadata.name == "test2-chart"
          && depl.metadata.namespace == "test2"
          && depl.metadata.labels
          == {
            "app.kubernetes.io/instance" = "test2";
            "app.kubernetes.io/managed-by" = "Helm";
            "app.kubernetes.io/name" = "chart";
          }
          && depl.spec.replicas == 3
          && container.name == "chart"
          && container.image == "nginx:1.0.0";
      }

      {
        description = "Helm chart with values override should render service correctly.";
        expression = apps.test2.resources.core.v1.Service.test2-chart;
        assertion = svc: let
          port = head svc.spec.ports;
        in
          svc.kind
          == "Service"
          && svc.metadata.name == "test2-chart"
          && svc.metadata.namespace == "test2"
          && svc.metadata.labels
          == {
            "app.kubernetes.io/instance" = "test2";
            "app.kubernetes.io/managed-by" = "Helm";
            "app.kubernetes.io/name" = "chart";
          }
          && svc.spec.type == "ClusterIP"
          && port.port == 8080
          && port.targetPort == "http"
          && port.protocol == "TCP"
          && port.name == "http";
      }

      {
        description = "Helm chart with unsupported resource types should still output the resource.";
        expression = apps.test2.objects;
        assertion = any (
          obj:
            obj.apiVersion
            == "cert-manager.io/v1"
            && obj.kind == "Issuer"
            && obj.metadata.name == "ca-issuer"
            && obj.metadata.labels
            == {
              "app.kubernetes.io/instance" = "test2";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            }
            && obj.spec.ca.secretName == "ca-key-pair"
        );
      }
    ];
  };
}
