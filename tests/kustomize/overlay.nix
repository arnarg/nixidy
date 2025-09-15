{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  # Create an application with the overlay kustomization
  # which overrides a value and adds an unknown resource
  # type
  applications.test1.kustomize.applications.test1 = {
    kustomization = {
      src = ./manifests;
      path = "overlay";
    };
  };

  test = with lib; {
    name = "kustomize overlay application";
    description = "Create an application with kustomize \"overlay\".";
    assertions = [
      {
        description = "Deployment should be rendered correctly.";

        expression = findFirst (
          x: x.kind == "Deployment" && x.metadata.name == "deployment"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "deployment";
            namespace = "test1";
            labels."app.kubernetes.io/name" = "deployment";
          };
          spec = {
            replicas = 3;
            selector.matchLabels."app.kubernetes.io/name" = "deployment";
            template = {
              metadata.labels."app.kubernetes.io/name" = "deployment";
              spec.containers = [
                {
                  name = "nginx";
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
        description = "Service should be rendered correctly.";

        expression = findFirst (
          x: x.kind == "Service" && x.metadata.name == "service"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "service";
            namespace = "test1";
            labels."app.kubernetes.io/name" = "service";
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
            selector."app.kubernetes.io/name" = "deployment";
          };
        };
      }

      {
        description = "Issuer should be rendered correctly.";

        expression = findFirst (
          x: x.kind == "Issuer" && x.metadata.name == "ca-issuer"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "cert-manager.io/v1";
          kind = "Issuer";
          metadata = {
            name = "ca-issuer";
            namespace = "test1";
            labels."app.kubernetes.io/name" = "ca-issuer";
          };
          spec.ca.secretName = "ca-key-pair";
        };
      }
    ];
  };
}
