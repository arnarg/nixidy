{
  lib,
  config,
  ...
}: let
  apps = config.applications;
in {
  applications = {
    # Create an application with a kustomization
    test1.kustomize.applications.test1 = {
      kustomization = {
        src = ./manifests;
        path = "base";
      };
    };

    # Create an application with the overlay kustomization
    # which overrides a value and adds an unknown resource
    # type
    test2.kustomize.applications.test2 = {
      kustomization = {
        src = ./manifests;
        path = "overlay";
      };
    };
  };

  test = with lib; {
    name = "kustomize applications";
    description = "Check that kustomize applications are rendered correctly.";
    assertions = [
      {
        description = "Deployment should be rendered correctly from base kustomization.";
        expression = apps.test1.resources.apps.v1.Deployment.deployment;
        assertion = depl: let
          container = head depl.spec.template.spec.containers;
        in
          depl.kind
          == "Deployment"
          && depl.metadata.name == "deployment"
          && depl.metadata.namespace == "test1"
          && depl.metadata.labels
          == {
            "app.kubernetes.io/name" = "deployment";
          }
          && depl.spec.replicas == 1
          && container.name == "nginx"
          && container.image == "nginx:latest";
      }

      {
        description = "Service should be rendered correctly from base kustomization.";
        expression = apps.test1.resources.core.v1.Service.service;
        assertion = svc: let
          port = head svc.spec.ports;
        in
          svc.kind
          == "Service"
          && svc.metadata.name == "service"
          && svc.metadata.namespace == "test1"
          && svc.metadata.labels
          == {
            "app.kubernetes.io/name" = "service";
          }
          && svc.spec.type == "ClusterIP"
          && port.port == 80
          && port.targetPort == "http"
          && port.protocol == "TCP"
          && port.name == "http";
      }

      {
        description = "Deployment should be rendered correctly from overlay kustomization.";
        expression = apps.test2.resources.apps.v1.Deployment.deployment;
        assertion = depl: let
          container = head depl.spec.template.spec.containers;
        in
          depl.kind
          == "Deployment"
          && depl.metadata.name == "deployment"
          && depl.metadata.namespace == "test2"
          && depl.metadata.labels
          == {
            "app.kubernetes.io/name" = "deployment";
          }
          && depl.spec.replicas == 3
          && container.name == "nginx"
          && container.image == "nginx:latest";
      }

      {
        description = "Service should be rendered correctly from overlay kustomization.";
        expression = apps.test2.resources.core.v1.Service.service;
        assertion = svc: let
          port = head svc.spec.ports;
        in
          svc.kind
          == "Service"
          && svc.metadata.name == "service"
          && svc.metadata.namespace == "test2"
          && svc.metadata.labels
          == {
            "app.kubernetes.io/name" = "service";
          }
          && svc.spec.type == "ClusterIP"
          && port.port == 80
          && port.targetPort == "http"
          && port.protocol == "TCP"
          && port.name == "http";
      }

      {
        description = "Unknown resource type should still be output in the applications.";
        expression = apps.test2.objects;
        assertion = any (
          obj:
            obj.apiVersion
            == "cert-manager.io/v1"
            && obj.kind == "Issuer"
            && obj.metadata.name == "ca-issuer"
            && obj.metadata.labels
            == {
              "app.kubernetes.io/name" = "ca-issuer";
            }
            && obj.spec.ca.secretName == "ca-key-pair"
        );
      }
    ];
  };
}
