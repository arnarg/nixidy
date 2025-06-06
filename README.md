# nixidy

[![LICENSE](https://img.shields.io/github/license/arnarg/nixidy)](./LICENSE)

Kubernetes GitOps with nix and Argo CD.

> Kind of sounds like Nix CD.

## What is it?

Manage an entire Kubernetes cluster like it's NixOS, then have CI generate plain YAML manifests for ArgoCD.

```nix
{
  applications.demo = {
    namespace = "demo";

    # Automatically generate a namespace resource with the
    # above set namespace
    createNamespace = true;

    resources = let
      labels = {
        "app.kubernetes.io/name" = "nginx";
      };
    in {
      # Define a deployment for running an nginx server
      deployments.nginx.spec = {
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            securityContext.fsGroup = 1000;
            containers.nginx = {
              image = "nginx:1.25.1";
              imagePullPolicy = "IfNotPresent";
              volumeMounts = {
                "/etc/nginx".name = "config";
                "/var/lib/html".name = "static";
              };
            };
            volumes = {
              config.configMap.name = "nginx-config";
              static.configMap.name = "nginx-static";
            };
          };
        };
      };

      # Define config maps with config for nginx
      configMaps = {
        nginx-config.data."nginx.conf" = ''
          user nginx nginx;
          error_log /dev/stdout info;
          pid /dev/null;
          events {}
          http {
            access_log /dev/stdout;
            server {
              listen 80;
              index index.html;
              location / {
                root /var/lib/html;
              }
            }
          }
        '';

        nginx-static.data."index.html" = ''
          <html><body><h1>Hello from NGINX</h1></body></html>
        '';
      };

      # Define service for nginx
      services.nginx.spec = {
        selector = labels;
        ports.http.port = 80;
      };
    };
  };
}
```

Then build with nixidy using `nixidy build .#prod`

```
tree -l result/
├── apps
│   └── Application-demo.yaml
└── demo
    ├── ConfigMap-nginx-config.yaml
    ├── ConfigMap-nginx-static.yaml
    ├── Deployment-nginx.yaml
    ├── Namespace-demo.yaml
    └── Service-nginx.yaml
```

## Key Features

- **Declarative Cluster Management**: Define your entire Kubernetes cluster state using the Nix language.
- **NixOS-like Experience**: Leverage the power and structure of the NixOS module system for your Kubernetes configurations.
- **GitOps Ready**: Generates plain YAML manifests, aligning with the "Rendered Manifests Pattern" for Argo CD.
- **Strongly-Typed Configuration**: Benefit from NixOS' type system for Kubernetes resources, catching errors early.
- **Simplified Multi-Environment Management**: Easily manage configurations for development, staging, production, etc.
- **Helm & Kustomize Integration**: Seamlessly incorporate existing Helm charts and Kustomize overlays.
- **Extensible**: Generate typed Nix options for your Custom Resource Definitions (CRDs).

## Getting Started

Take a look at the [getting started guide](https://arnarg.github.io/nixidy/user_guide/getting_started/).

## Examples

- [arnarg's cluster configuration](https://github.com/arnarg/cluster)

## Why nixidy?

It's desirable to manage Kubernetes clusters in a declarative way using a git repository as a source of truth for manifests that should be deployed into the cluster. One popular solution that is often used to achieve this goal is [Argo CD](https://argo-cd.readthedocs.io/).

Argo CD has a concept of applications. Each application has an entrypoint somewhere in your git repository that is either a Helm chart, kustomize application, jsonnet files or just a directory of YAML files. All the resources that are output when templating the helm chart, kustomizing the kustomize application or are defined in the YAML files in the directory, make up the application and are (usually) deployed into a single namespace.

For those reasons these git repositories often need quite elaborate designs once many applications should be deployed, requiring use of application sets (generator for applications) or custom Helm charts just to render all the different applications of the repository.

On top of that it can be quite obscure _what exactly_ will be deployed by just looking at helm charts (along with all the values override, usually set for each environment) or the kustomize overlays (which often are many depending on number of environments/stages) without going in and just running `helm template` or `kubectl kustomize`.

Having dealt with these design decisions and pains that come with the different approaches I'm starting to use [The Rendered Manifests Pattern](https://akuity.io/blog/the-rendered-manifests-pattern/). While it's explained in way more detail in the linked blog post, basically it involves using your CI system to pre-render the helm charts or the kustomize overlays and commit all the rendered manifests to an environment branch (or go through a pull request review where you can review the _exact_ changes to your environment). That way you can just point Argo CD to your different directories full of rendered YAML manifests without having to do any helm templating or kustomize rendering.

### NixOS' Module System

I have been a user and a fan of NixOS for many years and how its module system works to recursively merge all configuration options that are set in many different modules.

I have _not_ been a fan of helm's string templating of a whitespace-sensitive configuration language or kustomize's repetition (defining a `kustomization.yaml` file for each layer statically listing files to include, some are JSON patches some are not...).

Therefore I made nixidy as an experiment to see if I can make something better (at least for myself). As all Argo CD applications are defined in a single configuration it can reference configuration options across applications and automatically generate an [App of Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern) bootstrapping all of them.

## Special Thanks

[farcaller/nix-kube-generators](https://github.com/farcaller/nix-kube-generators) is used internally to pull and render Helm charts and some functions are re-exposed in the lib passed to modules in nixidy.

[hall/kubenix](https://github.com/hall/kubenix) project has code generation of nix module options for every standard kubernetes resource. Instead of doing this work in nixidy I import their generated resource options. The resource option generation scripts in nixidy are also a slight modification of kubenix's. Without their work this wouldn't be possible in nixidy.

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, documentation improvements, or code contributions, please feel free to open an issue or pull request on our [GitHub repository](https://github.com/arnarg/nixidy).

## License

nixidy is licensed under the [MIT License](./LICENSE).
