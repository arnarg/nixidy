# Getting Started

Nixidy only supports [Nix Flakes](https://nixos.wiki/wiki/Flakes) so that needs to be enabled.

## Initialize Repository

First a `flake.nix` needs to be created in the root of the repository.

```nix title="flake.nix"
{
  description = "My ArgoCD configuration with nixidy.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixidy.url = "github:arnarg/nixidy";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nixidy,
  }: (flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      inherit system;
    };
  in {
    # This declares the available nixidy envs.
    nixidyEnvs = nixidy.lib.mkEnvs {
      inherit pkgs;

      envs = {
        # Currently we only have the one dev env.
        dev.modules = [./env/dev.nix];
      };
    };

    # Handy to have nixidy cli available in the local
    # flake too.
    packages.nixidy = nixidy.packages.${system}.default;

    # Useful development shell with nixidy in path.
    # Run `nix develop` to enter.
    devShells.default = pkgs.mkShell {
      buildInputs = [nixidy.packages.${system}.default];
    };
  }));
}
```

The flake declares a single nixidy environment called `dev`. It includes a single nix module found at `./env/dev.nix`, so let's create that.

```nix title="env/dev.nix"
{
  # Set the target repository for the rendered manifests
  # and applications.
  # This should be replaced with yours, usually the same
  # repository as the nixidy definitions.
  nixidy.target.repository = "https://github.com/arnarg/nixidy-demo.git";

  # Set the target branch the rendered manifests for _this_
  # environment should be pushed to in the repository defined
  # above.
  nixidy.target.branch = "main";

  # Set the target sub-directory to copy the generated
  # manifests to when running `nixidy switch .#dev`.
  nixidy.target.rootPath = "./manifests/dev";
}
```

Now running `nix run .#nixidy -- info .#dev` (or `nixidy info .#dev` if run in nix shell using `nix develop`) you can get the same info we just declared above. This verifies that things are set up correctly so far.

```shell
>> nix run .#nixidy -- info .#dev
Repository: https://github.com/arnarg/nixidy-demo.git
Branch:     main
```

If we now attempt to build this new environment with `nix run .#nixidy -- build .#dev` we can see that nothing is generated but an empty folder called `apps`.

```shell
>> tree result
result
└── apps/
```

This is because we have not declared any applications yet for this environment.

## Our first Application

Applications and their resources are defined under `applications.<applicationName>`.

```nix title="env/dev.nix"
{
  # Set the target repository for the rendered manifests
  # and applications.
  # This should be replaced with yours, usually the same
  # repository as the nixidy definitions.
  nixidy.target.repository = "https://github.com/arnarg/nixidy-demo.git";

  # Set the target branch the rendered manifests for _this_
  # environment should be pushed to in the repository defined
  # above.
  nixidy.target.branch = "main";

  # Set the target sub-directory to copy the generated
  # manifests to when running `nixidy switch .#dev`.
  nixidy.target.rootPath = "./manifests/dev";

  # Define an application called `demo`.
  applications.demo = {
    # All resources will be deployed into this namespace.
    namespace = "demo";

    # Automatically generate a namespace resource for the
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

Running `nixidy build .#dev` will produce the following files.

```shell
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

And the contents of the Argo CD application automatically generated is the following:

```yaml title="apps/Application-demo.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  # This is the name of the application (`applications.demo`).
  name: demo
  namespace: argocd
spec:
  destination:
    # This is the destination namespace for the application
    # specified with `applications.demo.namespace`.
    namespace: demo
    server: https://kubernetes.default.svc
  project: default
  source:
    # This is the output path declared for the application with
    # option `applications.<applicationName>.output.path`
    # (defaults to the name) with `nixidy.target.rootPath`
    # prefix.
    path: ./manifests/dev/demo
    # Repository specified in `nixidy.target.repository`.
    repoURL: https://github.com/arnarg/nixidy-demo.git
    # Branch specified in `nixidy.target.branch`.
    targetRevision: main
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
```

A directory with rendered resources is generated for each application declared with `applications.<name>` as well as an Argo CD application resource YAML file in `apps/`. What this provides is the option to bootstrap the whole rendered branch to a cluster by adding an application pointing to the `apps/` folder.

See [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

Running `nixidy switch .#dev` will create the `./manifests/dev` relative to the current working directory and sync the newly generated manifests into it.
