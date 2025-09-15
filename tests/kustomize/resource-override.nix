{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  # Create an application with a kustomization
  # and a nixidy resource override
  applications.test1 = {
    kustomize.applications.test1.kustomization = {
      src = ./manifests;
      path = "base";
    };

    resources.deployments.deployment.spec.template.spec.containers.nginx.image =
      lib.mkForce "nginx:2.0.0";
  };

  test = with lib; {
    name = "kustomize application with resource override";
    description = "Create an application with kustomize \"base\" and override resource in nixidy.";
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
            replicas = 1;
            selector.matchLabels."app.kubernetes.io/name" = "deployment";
            template = {
              metadata.labels."app.kubernetes.io/name" = "deployment";
              spec.containers = [
                {
                  name = "nginx";
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
    ];
  };
}
