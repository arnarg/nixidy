{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  applications = {
    # Create an application with yamls
    test1.yamls = [
      # One Service object which always has resource
      # types for
      ''
        apiVersion: v1
        kind: Service
        metadata:
          name: my-svc
          labels:
            name: my-svc
        spec:
          type: ClusterIP
          ports:
            - port: 80
              targetPort: http
              protocol: TCP
              name: http
          selector:
            name: my-svc
      ''

      # One Issuer which is does not have resource
      # types defined
      ''
        apiVersion: cert-manager.io/v1
        kind: Issuer
        metadata:
          name: ca-issuer
        spec:
          ca:
            secretName: ca-key-pair
      ''
    ];

    # Create an application with yamls and a
    # resource override
    test2 = {
      yamls = [
        ''
          apiVersion: v1
          kind: Service
          metadata:
            name: my-svc
            labels:
              name: my-svc
          spec:
            type: ClusterIP
            ports:
              - port: 80
                targetPort: http
                protocol: TCP
                name: http
            selector:
              name: my-svc
        ''
      ];

      resources.services.my-svc.spec.ports.http.port = lib.mkForce 8080;
    };
  };

  test = with lib; {
    name = "custom yamls";
    description = "Check that extra custom yamls are parsed an output with resources.";
    assertions = [
      {
        description = "Service should be parsed correctly.";

        expression = findFirst (
          x: x.kind == "Service" && x.metadata.name == "my-svc"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "my-svc";
            namespace = "test1";
            labels.name = "my-svc";
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
            selector.name = "my-svc";
          };
        };
      }

      {
        description = "Custom yaml of unsupported resource types should still be in the resources output.";

        expression = findFirst (
          x: x.kind == "Issuer" && x.metadata.name == "ca-issuer"
        ) null apps.test1.objects;

        expected = {
          apiVersion = "cert-manager.io/v1";
          kind = "Issuer";
          metadata.name = "ca-issuer";
          spec.ca.secretName = "ca-key-pair";
        };
      }

      {
        description = "Service should be overridden correctly.";

        expression = findFirst (
          x: x.kind == "Service" && x.metadata.name == "my-svc"
        ) null apps.test2.objects;

        expected = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "my-svc";
            namespace = "test2";
            labels.name = "my-svc";
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
            selector.name = "my-svc";
          };
        };
      }
    ];
  };
}
