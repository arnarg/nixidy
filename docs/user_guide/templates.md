# Templates

Templates provide a powerful way to define reusable configurations for your applications, reducing duplication and promoting consistency. A template encapsulates a set of configurable options and a function to generate Kubernetes resources based on those options.

## Defining a Template

You define templates within the `templates` option in your nixidy configuration. Each template requires two main attributes:

- `options`: A set of module options that define the configurable parameters for your template.
- `output`: A Nix function that takes the template instance's `name` and its `config` (derived from the `options` you defined) and returns a set of nixidy resources (e.g., deployments, services, ingresses).

### Example: `webApplication` Template

Let's look at an example of a `webApplication` template, which defines common settings for a web application and generates a Kubernetes Deployment, Service, and an optional Ingress.

```nix title="modules/templates.nix"
{lib, ...}: {
  templates.webApplication = {
    options = with lib; {
      image = mkOption {
        type = lib.types.str;
        description = "The image to use in the web application deployment";
      };
      replicas = mkOption {
        type = lib.types.int;
        default = 3;
        description = "The number of replicas for the web application deployment.";
      };
      port = mkOption {
        type = lib.types.port;
        default = 8080;
        description = "The web application's port.";
      };
      ingressHost = mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = "The application's ingress host. Set to null to disable ingress.";
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

      ingresses = lib.mkIf (cfg.ingressHost != null) {
        "${name}".spec = {
          rules = [
            {
              host = cfg.ingressHost;
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
}
```

In this example:

- The `webApplication` template defines `image`, `replicas`, `port`, and `ingressHost` as configurable options.
- The `output` function takes the `name` of the instance and its `config` (which will contain the values for `image`, `replicas`, etc.). It then uses these values to construct Kubernetes Deployment, Service, and Ingress resources.

## Using a Template

Once a template is defined you can use it within an application by referring to it under the `templates` attribute set of your application.

```nix title="modules/webapp.nix"
{ config, lib, ... }: {
  imports = [
    ./templates.nix
  ];

  applications.webapp = {
    templates.webApplication = {
      # Use the template in an application.
      frontend = {
        image = "frontend:latest";
        replicas = 1;
        ingressHost = "example.com";
      };
    };

    # You can still modify the generated resources.
    resources = {
      # Add extra label to the deployment.
      deployments.frontend.metadata.labels = {
        "custom-label" = "frontend";
      };
    };
  };
}
```

Here, `applications.webapp.templates.webApplication.frontend` instantiates the `webApplication` template.

- `webApplication` refers to the name of the template we defined.
- `frontend` is the instance name for this specific use of the template. This name is passed to the `output` function as `name`.
- The attributes `image`, `replicas`, and `ingressHost` are the options we're setting for this `frontend` instance of the `webApplication` template. The `port` option is omitted, so it will use its default value of `8080`.

When nixidy evaluates this configuration, it will call the `output` function of the `webApplication` template with `name = "frontend"` and `config` containing the provided options, generating the corresponding Kubernetes resources under `applications.webapp.resources`.
