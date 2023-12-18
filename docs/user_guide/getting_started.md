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
