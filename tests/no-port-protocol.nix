{
  config,
  lib,
  ...
}: let
  apps = config.applications;
in {
  applications.test1.resources.pods.nginx-pod.spec.containers.nginx = {
    image = "nginx:latest";
    ports = {
      dns = {
        containerPort = 53;
        protocol = "UDP";
      };
      dnstcp.containerPort = 53;
    };
  };

  applications.test2.resources.pods.nginx-pod.spec.containers.nginx = {
    image = "nginx:latest";
    ports = [
      {
        name = "dns";
        containerPort = 53;
        protocol = "UDP";
      }
      {
        containerPort = 53;
      }
    ];
  };

  applications.test3.resources.services.nginx-service.spec = {
    ports = [
      {
        name = "dns";
        port = 53;
        protocol = "UDP";
      }
      {
        port = 53;
      }
    ];
  };

  test = {
    name = "service/container port with/without protocol";
    description = "Check that specifying a port without protocol works.";
    assertions = [
      {
        description = "Pod ports defined using attrset.";

        expression = lib.findFirst (obj: obj.metadata.name == "nginx-pod") null apps.test1.objects;

        assertion = pod: let
          checkPodPorts = pod: let
            ports = (builtins.head pod.spec.containers).ports;
            port1 = builtins.elemAt ports 0;
            port2 = builtins.elemAt ports 1;
          in
            port1.name
            == "dns"
            && port1.containerPort == 53
            && port1.protocol == "UDP"
            && port2.name == "dnstcp"
            && port2.containerPort == 53
            && !(builtins.hasAttr "protocol" port2);
        in
          pod
          != null
          && (checkPodPorts pod);
      }

      {
        description = "Pod ports defined using list.";

        expression = lib.findFirst (obj: obj.metadata.name == "nginx-pod") null apps.test2.objects;

        assertion = pod: let
          checkPodPorts = pod: let
            ports = (builtins.head pod.spec.containers).ports;
            port1 = builtins.elemAt ports 0;
            port2 = builtins.elemAt ports 1;
          in
            port1.name
            == "dns"
            && port1.containerPort == 53
            && port1.protocol == "UDP"
            && port2.containerPort == 53
            && !(builtins.hasAttr "name" port2)
            && !(builtins.hasAttr "protocol" port2);
        in
          pod
          != null
          && (checkPodPorts pod);
      }

      {
        description = "Service ports defined using list.";

        expression = lib.findFirst (obj: obj.metadata.name == "nginx-service") null apps.test3.objects;

        assertion = service: let
          checkServicePorts = service: let
            ports = service.spec.ports;
            port1 = builtins.elemAt ports 0;
            port2 = builtins.elemAt ports 1;
          in
            port1.name == "dns"
            && port1.port == 53
            && port1.protocol == "UDP"
            && port2.port == 53
            && !(builtins.hasAttr "name" port2)
            && !(builtins.hasAttr "protocol" port2);
        in
          service
          != null
          && (checkServicePorts service);
      }
    ];
  };
}
