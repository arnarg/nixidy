{
  config,
  lib,
  ...
}: let
  apps = config.applications;
in {
  # Define a webApplication template
  templates.webApplication = {
    options = with lib; {
      image = mkOption {
        type = lib.types.str;
      };
      replicas = mkOption {
        type = lib.types.int;
        default = 3;
      };
      port = mkOption {
        type = lib.types.port;
        default = 8080;
      };
      ingress.host = mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };
    };

    output = {
      name,
      config,
      ...
    }: let
      cfg = config;
      appLabels = {
        "app.kubernetes.io/name" = name;
        "app.kubernetes.io/instance" = name;
      };
    in {
      deployments."${name}".spec = {
        replicas = cfg.replicas;
        selector.matchLabels = appLabels;
        template = {
          metadata.labels = appLabels;
          spec.containers."${name}" = {
            image = cfg.image;
            ports."http".containerPort = cfg.port;
          };
        };
      };

      services."${name}".spec = {
        selector = appLabels;
        ports.http = {
          port = cfg.port;
          targetPort = cfg.port;
        };
      };

      ingresses = lib.mkIf (cfg.ingress.host != null) {
        "${name}".spec = {
          rules = [
            {
              host = cfg.ingress.host;
              http.paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                  backend.service = {
                    inherit name;
                    port.number = cfg.port;
                  };
                }
              ];
            }
          ];
        };
      };
    };
  };

  # Use the template in an application
  applications.test1 = {
    templates.webApplication.app1 = {
      image = "test-image:latest";
      replicas = 1;
      ingress.host = "app1.example.com";
    };
  };

  # Test assertions
  test = with lib; {
    name = "using templates";
    description = "Check that user provided templates work as expected.";
    assertions = [
      {
        description = "Deployment should be rendered correctly";

        expression =
          findFirst
          (x: x.kind == "Deployment" && x.metadata.name == "app1")
          null
          apps.test1.objects;

        assertion = obj: let
          checkPorts = ports: let
            port = builtins.head ports;
          in
            port.name
            == "http"
            && port.containerPort == 8080;

          checkContainer = cnts: let
            cnt = builtins.head cnts;
          in
            cnt.name
            == "app1"
            && cnt.image == "test-image:latest"
            && checkPorts cnt.ports;
        in
          obj
          != null
          && obj.metadata.name == "app1"
          && obj.spec.replicas == 1
          && obj.spec.selector.matchLabels
          == {
            "app.kubernetes.io/name" = "app1";
            "app.kubernetes.io/instance" = "app1";
          }
          && obj.spec.template.metadata.labels
          == {
            "app.kubernetes.io/name" = "app1";
            "app.kubernetes.io/instance" = "app1";
          }
          && checkContainer obj.spec.template.spec.containers;
      }

      {
        description = "Service should be rendered correctly";

        expression =
          findFirst
          (x: x.kind == "Service" && x.metadata.name == "app1")
          null
          apps.test1.objects;

        assertion = obj: let
          checkPorts = ports: let
            port = builtins.head ports;
          in
            port.name
            == "http"
            && port.port == 8080
            && port.targetPort == 8080;
        in
          obj
          != null
          && obj.metadata.name == "app1"
          && obj.spec.selector
          == {
            "app.kubernetes.io/name" = "app1";
            "app.kubernetes.io/instance" = "app1";
          }
          && checkPorts obj.spec.ports;
      }

      {
        description = "Ingress should be rendered correctly";

        expression =
          findFirst
          (x: x.kind == "Ingress" && x.metadata.name == "app1")
          null
          apps.test1.objects;

        assertion = obj: let
          rule = builtins.head obj.spec.rules;
          path = builtins.head rule.http.paths;
        in
          obj
          != null
          && obj.metadata.name == "app1"
          && rule.host == "app1.example.com"
          && path.path == "/"
          && path.pathType == "Prefix"
          && path.backend.service.name == "app1"
          && path.backend.service.port.number == 8080;
      }
    ];
  };
}
