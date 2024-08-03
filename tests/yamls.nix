{
  lib,
  config,
  ...
}: let
  apps = config.applications;
in {
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
  };

  test = with lib; {
    name = "custom yamls";
    description = "Check that extra custom yamls are parsed an output with resources.";
    assertions = [
      {
        description = "Service should be parsed correctly.";
        expression = apps.test1.resources.core.v1.Service.my-svc;
        assertion = svc: let
          port = head svc.spec.ports;
        in
          svc.kind
          == "Service"
          && svc.metadata.name == "my-svc"
          && svc.metadata.namespace == "test1"
          && svc.metadata.labels
          == {
            name = "my-svc";
          }
          && svc.spec.type == "ClusterIP"
          && port.port == 80
          && port.targetPort == "http"
          && port.protocol == "TCP"
          && port.name == "http";
      }

      {
        description = "Custom yaml of unsupported resource types should still be in the resources output.";
        expression = apps.test1.objects;
        assertion = any (
          obj:
            obj.apiVersion
            == "cert-manager.io/v1"
            && obj.kind == "Issuer"
            && obj.metadata.name == "ca-issuer"
            && obj.spec.ca.secretName == "ca-key-pair"
        );
      }
    ];
  };
}
