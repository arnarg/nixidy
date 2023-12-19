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
  # When using `mkEnvs` function in flake.nix it wil automatically
  # set this to `"env/${name}"`.
  nixidy.target.branch = "env/dev";
}
```

Now runnig `nix run .#nixidy -- info .#dev` (or simply `nixidy info .#dev` if run in nix shell using `nix develop`) you can get the same info we just declared above. This verifies that things are set up correctly so far.

```shell
>> nix run .#nixidy -- info .#dev
Repository: https://github.com/arnarg/nixidy-demo.git
Branch:     env/dev
```

If we now attempt to build this new environment with `nix run .#nixidy -- build .#dev` we can see that nothing is generated but an empty folder called `apps`.

```shell
>> tree result
result
└── apps/
```

This is because we have not declared any applications yet for this environment.

## Our first Application

While nixidy allows you to declare all of the application's resources directly in nix it would be a waste to not be able to use Helm charts and Kustomize applications that already exists and are often officially maintained by project maintainers.

The application's declaration is very similar whichever option you go with.

=== "Helm"

    ```nix title="env/dev.nix"
    {lib, ...}: {
      # Options explained in the section above.
      nixidy.target.repository = "https://github.com/arnarg/nixidy-demo.git";
      nixidy.target.branch = "env/dev";

      # Argo CD application using the Helm chart from argo-helm.
      applications.argocd = {
        # Declare the destination namespace for the application.
        namespace = "argocd";

        # Instruct nixidy to automatically create a `Namespace`
        # manifest in the rendered manifests for namespace
        # selected above.
        createNamespace = true;

        # Specify Helm chart with values to template with.
        helm.releases.argocd = {
          # Using `downloadHelmChart` we can download
          # the helm chart using nix.
          # The value for `chartHash` needs to be updated
          # with each version.
          chart = lib.helm.downloadHelmChart {
            repo = "https://argoproj.github.io/argo-helm/";
            chart = "argo-cd";
            version = "5.51.6";
            chartHash = "sha256-3kRkzOQdYa5JkrBV/+iJK3FP+LDFY1J8L20aPhcEMkY=";
          };

          # Specify values to pass to the chart.
          values = {
            # Run argocd-server with 2 replicas.
            # This is an option in the chart's `values.yaml`
            # usually declared like this:
            #
            # server:
            #   replicas: 2
            server.replicas = 2;
          };
        };
      };
    }
    ```

=== "Kustomize"

    ```nix title="env/dev.nix"
    {pkgs, ...}: {
      # Options explained in the section above.
      nixidy.target.repository = "https://github.com/arnarg/nixidy-demo.git";
      nixidy.target.branch = "env/dev";

      # Argo CD application using the official kustomize application
      # from Argo CD git repository.
      applications.argocd = {
        # Declare the destination namespace for the application.
        namespace = "argocd";

        # Instruct nixidy to automatically create a `Namespace`
        # manifest in the rendered manifests for namespace
        # selected above.
        createNamespace = true;

        # Specify Kustomize application to render.
        kustomize.applications.argocd = {
          # Equivalent to `github.com/argoproj/argo-cd/manifests/cluster-install?ref=v2.9.3`
          # in kustomization.yaml.
          kustomization = {
            src = pkgs.fetchFromGitHub {
              owner = "argoproj";
              repo = "argo-cd";
              rev = "v2.9.3";
              hash = "sha256-GaY4Cw/LlSwy35umbB4epXt6ev8ya19UjHRwhDwilqU=";
            };
            path = "manifests/cluster-install";
          };
        };
      };
    }
    ```

In both cases the following output will be generated:

```shell
tree -l result
├── apps
│   └── Application-argocd.yaml
└── argocd
    ├── ClusterRole-argocd-application-controller.yaml
    ├── ClusterRole-argocd-server.yaml
    ├── ClusterRoleBinding-argocd-application-controller.yaml
    ├── ClusterRoleBinding-argocd-server.yaml
    ├── ConfigMap-argocd-cmd-params-cm.yaml
    └── ...
```

And the contents of the Argo CD application automatically generated is the following:

```yaml title="apps/Application-argocd.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  # This is the name of the application (`applications.argocd`).
  name: argocd 
  namespace: argocd
spec:
  destination:
    # This is the destination namespace for the application
    # specified with `applications.argocd.namespace`.
    namespace: argocd
    server: https://kubernetes.default.svc
  project: default
  source:
    # This is the output path declared for the application with
    # option `applications.output.path` (defaults to the name).
    path: argocd
    # Repository specified in `nixidy.target.repository`.
    repoURL: https://github.com/arnarg/nixidy-demo.git
    # Branch specified in `nixidy.target.branch`.
    targetRevision: env/dev
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
```

A directory with rendered resources is generated for each application declared with `applications.<name>` as well as an Argo CD application resource YAML file in `apps/`. What this provides is the option to bootstrap the whole rendered branch to a cluster by adding an application pointing to the `apps/` folder.

See [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern).

## Modularizing the Configuration

So far we've initialized the repository with `flake.nix` and a single environment with all options set in a single file (`env/dev.nix`). Next we'll want to add a `test` environment.

Adding a test environment is as simple as copying `env/dev.nix` to `env/test.nix`, renaming the target branch and adding that to `flake.nix` under `envs.test.modules`. This however will involve a lot of code duplication and the environment will need to be maintained completely separately.

Instead we should modularize the configuration into re-usable modules that can allow slight modification between environments (number of replicas, ingress domain, etc.).

To start this migration a `modules/default.nix` should be created.


=== "Helm"

    ```nix title="modules/default.nix"
    {lib, ...}: {
      # This option should be common across all environments so we
      # can declare it here.
      nixidy.target.repository = "https://github.com/arnarg/nixidy-demo.git";

      # Argo CD application using the Helm chart from argo-helm.
      applications.argocd = {
        # Declare the destination namespace for the application.
        namespace = "argocd";

        # Instruct nixidy to automatically create a `Namespace`
        # manifest in the rendered manifests for namespace
        # selected above.
        createNamespace = true;

        # Specify Helm chart with values to template with.
        helm.releases.argocd = {
          # Using `downloadHelmChart` we can download
          # the helm chart using nix.
          # The value for `chartHash` needs to be updated
          # with each version.
          chart = lib.helm.downloadHelmChart {
            repo = "https://argoproj.github.io/argo-helm/";
            chart = "argo-cd";
            version = "5.51.6";
            chartHash = "sha256-3kRkzOQdYa5JkrBV/+iJK3FP+LDFY1J8L20aPhcEMkY=";
          };

          # Specify values to pass to the chart.
          values = {
            # Run argocd-server with 2 replicas.
            # This is an option in the chart's `values.yaml`
            # usually declared like this:
            #
            # server:
            #   replicas: 2
            server.replicas = 2;
          };
        };
      };
    }
    ```

=== "Kustomize"

    ```nix title="modules/default.nix"
    {pkgs, ...}: {
      # This option should be common across all environments so we
      # can declare it here.
      nixidy.target.repository = "https://github.com/arnarg/nixidy-demo.git";

      # Argo CD application using the official kustomize application
      # from Argo CD git repository.
      applications.argocd = {
        # Declare the destination namespace for the application.
        namespace = "argocd";

        # Instruct nixidy to automatically create a `Namespace`
        # manifest in the rendered manifests for namespace
        # selected above.
        createNamespace = true;

        # Specify Kustomize application to render.
        kustomize.applications.argocd = {
          # Equivalent to `github.com/argoproj/argo-cd/manifests/cluster-install?ref=v2.9.3`
          # in kustomization.yaml.
          kustomization = {
            src = pkgs.fetchFromGitHub {
              owner = "argoproj";
              repo = "argo-cd";
              rev = "v2.9.3";
              hash = "sha256-GaY4Cw/LlSwy35umbB4epXt6ev8ya19UjHRwhDwilqU=";
            };
            path = "manifests/cluster-install";
          };
        };
      };
    }
    ```

And in `flake.nix` we can now set it to use `modules/default.nix` as a common module like the following:

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

      # Modules to include in all envs.
      modules = [./modules];

      envs = {
        dev.modules = [./env/dev.nix];
        test.modules = [./env/test.nix];
      };
    };
  }));
}
```

Both environment specific files now only declare the target branch:

```nix title="env/dev.nix"
{
  nixidy.target.branch = "env/dev";
}
```

```nix title="env/test.nix"
{
  nixidy.target.branch = "env/test";
}
```

## Abstracting Options on top of Applications

Now we have all common configuration in a module that is used across all environments and the next step is to also add traefik as an ingress controller. Oh! and we also want to create an ingress for Argo CD Web UI using the ingress controller. Also, come to think of it, We also don't want to run 2 replicas of argocd-server in the dev environment to save on resources.

Reaching these goals is simple enough by overriding the few needed options directly in the env specific configuration, for example:

```nix title="env/dev.nix"
{lib, ...}: {
  # ...

  applications.argocd.helm.releases.argocd.values = {
    # Actually we want 1 replica only in dev.
    server.replicas = lib.mkForce 1;
  };
}
```

But this requires knowing the implementation details of the application and introduces tight coupling and things become hard to change for the argocd application.

Instead things should ideally be broken apart further and create an extra configuration interface on top. To achieve this we want to break the common modules into more files, or a module per application but with a common entrypoint.

### Traefik

Let's start by creating a module for traefik:

```nix title="modules/traefik.nix"
{
  lib,
  config,
  ...
}: {
  options.networking.traefik = with lib; {
    enable = mkEnableOption "traefik ingress controller";
    # Exposing some options that _could_ be set directly
    # in the values option below can be useful for discoverability
    # and being able to reference in other modules
    ingressClass = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether or not an ingress class for traefik should be created automatically.
        '';
      };
      name = mkOption {
        type = types.str;
        default = "traefik";
        description = ''
          The name of the ingress class for traefik that should be created automatically.
        '';
      };
    };
    # To not limit the consumers of this module allowing for
    # setting the helm values directly is useful in certain
    # situations
    values = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = ''
        Value overrides that will be passed to the helm chart.
      '';
    };
  };

  # Only create the application if traefik is enabled
  config = lib.mkIf config.networking.traefik.enable {
    applications.traefik = {
      namespace = "traefik";
      createNamespace = true;

      helm.releases.traefik = {
        chart = lib.helm.downloadHelmChart {
          repo = "https://traefik.github.io/charts/";
          chart = "traefik";
          version = "25.0.0";
          chartHash = "sha256-ua8KnUB6MxY7APqrrzaKKSOLwSjDYkk9tfVkb1bqkVM=";
        };

        # Here we merge default values with provided
        # values from `config.networking.traefik.values`.
        values = lib.recursiveUpdate {
          ingressClass = {
            enabled = config.networking.traefik.ingressClass.enable;
            name = config.networking.traefik.ingressClass.name;
          };
        } config.networking.traefik.values;
      };
    };
  };
}
```

Here we have declared extra configuration options that can be set in other modules. By setting `#!nix networking.traefik.enable = true;` the `traefik` application will be added, otherwise not. By setting `#!nix networking.traefik.ingressClass.enable = false;` the application will not contain an ingress class for traefik, and so on.

### Argo CD

Now let's create a specific module for Argo CD:

```nix title="modules/argocd.nix"
{
  lib,
  config,
  ...
}: {
  options.services.argocd = with lib; {
    enable = mkEnableOption "argocd";
    # Configuration options for the ingress
    ingress = {
      enable = mkEnableOption "argocd ingress";
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Hostname to use in the Ingress for argocd-server.
        '';
      };
      ingressClassName = mkOption {
        type = types.str;
        default = "";
        description = ''
          The ingress class to use in the Ingress for argocd-server.
        '';
      };
    };
    # Configuration option for setting the replicas for
    # argocd-server
    replicas = mkOption {
      type = types.int;
      default = 2;
      description = ''
        Number of replicas of the argocd-server deployment.
      '';
    };
    # To not limit the consumers of this module allowing for
    # setting the helm values directly is useful in certain
    # situations
    values = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = ''
        Value overrides that will be passed to the helm chart.
      '';
    };
  };

  # Only create the application if argocd is enabled
  config = lib.mkIf config.services.argocd.enable {
    applications.argocd = {
      namespace = "argocd";
      createNamespace = true;

      helm.releases.argocd = {
        chart = lib.helm.downloadHelmChart {
          repo = "https://argoproj.github.io/argo-helm/";
          chart = "argo-cd";
          version = "5.51.6";
          chartHash = "sha256-3kRkzOQdYa5JkrBV/+iJK3FP+LDFY1J8L20aPhcEMkY=";
        };

        # Here we merge default values with provided
        # values from `config.services.argocd.values`.
        values = lib.recursiveUpdate {
          # Set number of replicas by using service option
          server.replicas = config.services.argocd.replicas;
          # Create an ingress with the configured hostname
          server.ingress = {
            enabled = config.services.argocd.ingress.enable;
            ingressClassName = config.services.argocd.ingress.ingressClassName;
            hosts =
              if !isNull config.services.argocd.ingress.host
              then [config.services.argocd.ingress.host]
              else [];
          };
        } config.services.argocd.values;
      };
    };
  };
}
```

Like with the traefik module you can now set `#!nix services.argocd.enable = true;` to enable the argocd application and `#!nix services.argocd.ingress.enable = true;` to create an ingress.

### Putting it all together

Now with argocd and traefik declared in their own modules we will need to import them in the base `modules/default.nix`:

```nix title="modules/default.nix"
{lib, config, ...}: {
  # Here we import the modules we created above.
  # This will make all the configuration options
  # available to other modules.
  imports = [
    ./argocd.nix
    ./traefik.nix
  ];

  # This option should be common across all environments so we
  # can declare it here.
  nixidy.target.repository = "https://github.com/arnarg/nixidy-demo.git";

  # Traefik should be enable by default.
  networking.traefik.enable = lib.mkDefault true;

  # Argo CD should be enabled by default.
  services.argocd = {
    enable = lib.mkDefault true;

    ingress = {
      # An ingress for Argo CD Web UI should
      # be created if traefik is also enabled.
      enable = lib.mkDefault config.networking.traefik.enable;

      # The ingress should use Treafik's ingress
      # class.
      ingressClassName = lib.mkDefault config.networking.traefik.ingressClass.name;
    };
  };
}
```

This will import the two application modules and set some defaults by using `mkDefault` (this function sets the value as a default value but still allows overriding it in other modules). Notably we have set it up in a way that will automatically enable the ingress for Argo CD Web UI _if_ traefik is also enabled, which is also enabled in this file but can be still be disabled in another module.

Now in order to achieve the goals we set out to achieve in the beginning of this section, the following options are set in the environments' configurations:

```nix title="env/dev.nix"
{
  nixidy.target.branch = "env/dev";

  # We want to set the hostname for ArgoCD Web UI
  services.argocd.ingress.host = "argocd.dev.domain.com";

  # We only want 1 replica of argocd server
  services.argocd.replicas = 1;
}
```

```nix title="env/test.nix"
{
  nixidy.target.branch = "env/test";

  # We want to set the hostname for ArgoCD Web UI
  services.argocd.ingress.host = "argocd.test.domain.com";
}
```

Now the following manifests are generated:

```shell
>> tree -l result
result
├── apps
│   ├── Application-argocd.yaml
│   └── Application-traefik.yaml
├── argocd
│   ├── ClusterRole-argocd-application-controller.yaml
│   ├── ClusterRole-argocd-notifications-controller.yaml
│   ├── ClusterRole-argocd-repo-server.yaml
│   ├── ClusterRole-argocd-server.yaml
│   ├── ClusterRoleBinding-argocd-application-controller.yaml
│   └── ...
└── traefik
    ├── ClusterRoleBinding-traefik-traefik.yaml
    ├── ClusterRole-traefik-traefik.yaml
    ├── CustomResourceDefinition-ingressroutes-traefik-containo-us.yaml
    ├── CustomResourceDefinition-ingressroutes-traefik-io.yaml
    ├── CustomResourceDefinition-ingressroutetcps-traefik-containo-us.yaml
    └── ...
```
