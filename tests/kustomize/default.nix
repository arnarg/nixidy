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

        expression =
          findFirst
          (x: x.kind == "Deployment" && x.metadata.name == "deployment")
          null
          apps.test1.objects;

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
        description = "Service should be rendered correctly from base kustomization.";

        expression =
          findFirst
          (x: x.kind == "Service" && x.metadata.name == "service")
          null
          apps.test1.objects;

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
        description = "Deployment should be rendered correctly from overlay kustomization.";

        expression =
          findFirst
          (x: x.kind == "Deployment" && x.metadata.name == "deployment")
          null
          apps.test2.objects;

        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "deployment";
            namespace = "test2";
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
        description = "Service should be rendered correctly from overlay kustomization.";

        expression =
          findFirst
          (x: x.kind == "Service" && x.metadata.name == "service")
          null
          apps.test2.objects;

        expected = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "service";
            namespace = "test2";
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
        description = "Unknown resource type should still be output in the applications.";

        expression =
          findFirst
          (x: x.kind == "Issuer" && x.metadata.name == "ca-issuer")
          null
          apps.test2.objects;

        expected = {
          apiVersion = "cert-manager.io/v1";
          kind = "Issuer";
          metadata = {
            name = "ca-issuer";
            namespace = "test2";
            labels."app.kubernetes.io/name" = "ca-issuer";
          };
          spec.ca.secretName = "ca-key-pair";
        };
      }
    ];
  };
}
