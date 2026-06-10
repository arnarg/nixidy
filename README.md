<p align="center">
  <a href="https://nixidy.dev"><img alt="nixidy logo" src="./logo.svg" /></a><br />
  <a href="https://github.com/arnarg/nixidy/blob/main/LICENSE"><img src="https://img.shields.io/github/license/arnarg/nixidy?style=flat" alt="License Badge" /></a>
  <a href="https://github.com/arnarg/nixidy/releases"><img src="https://img.shields.io/github/v/tag/arnarg/nixidy?style=flat&label=release&color=0a7cbd" alt="Latest Release Badge" /></a>
  <img src="https://img.shields.io/github/check-runs/arnarg/nixidy/main?style=flat" alt="Checks Passing Badge" />
</p>

<p align="center">Kubernetes GitOps with nix and Argo CD.</p>

<p align="center">
  <a href="https://nixidy.dev/user_guide/getting_started/">Getting Started</a> •
  <a href="https://nixidy.dev/">Documentation</a> •
  <a href="#features">Features</a> •
  <a href="#resources">Resources</a>
</p>

## Why Nixidy?

Managing Kubernetes configurations at scale is hard. Helm charts require complex value overrides, Kustomize leads to repetitive overlays, and raw YAML becomes unmaintainable. Reviewing changes across environments is nearly impossible.

**Nixidy solves this** by bringing the power of Nix and the NixOS module system to Kubernetes:

- **Declarative**: Define your entire cluster state in one place
- **Typed**: Catch configuration errors before deployment
- **Composable**: Build complex configurations from reusable modules
- **Reviewable**: Generate plain YAML for easy PR reviews
- **Reproducible**: Same input always produces the same output

## How It Works

Define your Kubernetes resources using Nix:

```nix
{
  applications.demo = {
    namespace = "demo";
    createNamespace = true;

    resources = {
      deployments.nginx.spec = {
        replicas = 3;
        selector.matchLabels.app = "nginx";
        template = {
          metadata.labels.app = "nginx";
          spec.containers.nginx = {
            image = "nginx:1.25.1";
            ports.http.containerPort = 80;
          };
        };
      };

      services.nginx.spec = {
        selector.app = "nginx";
        ports.http.port = 80;
      };
    };
  };
}
```

Build with nixidy:

```sh
nixidy build .#prod
```

Get clean, reviewable YAML:

```
result/
├── apps/
│   └── Application-demo.yaml
└── demo/
    ├── Deployment-nginx.yaml
    ├── Namespace-demo.yaml
    └── Service-nginx.yaml
```

Argo CD picks up the changes, after committing the new manifests to your repository, and deploys to your cluster. That's it.

## Features

### 🎯 Declarative Cluster Management

Define your entire cluster state using Nix. No more scattered YAML files, Helm value overrides, or Kustomize patches. Everything in one place, with one language.

### 🔒 Strongly-Typed Configuration

Every Kubernetes resource is typed. Catch typos and validate configurations before they hit your cluster.

```nix
# This will error at build time, not runtime
resources.deployments.nginx.spec.replicas = "three"; # Type error!
```

### 📦 First-Class Helm Support

Use existing Helm charts without giving up control. Override values, patch resources, and clean up Helm artifacts.

```nix
applications.traefik = {
  namespace = "traefik";

  helm.releases.traefik = {
    chart = lib.helm.downloadHelmChart {
      repo = "https://traefik.github.io/charts/";
      chart = "traefik";
      version = "25.0.0";
      chartHash = "sha256-ua8KnUB6MxY7APqrrzaKKSOLwSjDYkk9tfVkb1bqkVM=";
    };
    values = {
      ingressClass.enabled = true;
    };
  };

  # Patch Helm output with nixidy
  resources.deployments.traefik.spec.replicas = lib.mkForce 5;
};
```

### 🔧 Kustomize Integration

Seamlessly incorporate Kustomize applications:

```nix
applications.argocd.kustomize.applications.argocd = {
  namespace = "argocd";
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
```

### 🌍 Multi-Environment Made Easy

Manage dev, staging, and production with shared base configurations and environment-specific overrides:

```nix
# base.nix - shared configuration
{lib, ...}: {
  applications.api.resources.deployments.api.spec = {
    replicas = lib.mkDefault 1;
    selector.matchLabels.app = "api";
    template.spec.containers.api.image = "api:latest";
  };
}

# prod.nix - production overrides
{lib, ...}: {
  imports = [ ./base.nix ];
  applications.api.resources.deployments.api.spec = {
    replicas = lib.mkForce 10;
    template.spec.containers.api.resources = {
      requests.memory = "512Mi";
      limits.memory = "1Gi";
    };
  };
}
```

### 🏗️ Reusable Templates

Create templates for common patterns and reuse them across applications:

```nix
templates.webApp = {
  options = {
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
  };
  output = { name, config, ... }: {
    deployments.${name}.spec = {
      replicas = config.replicas;
      selector.matchLabels.app = name;
      template = {
        metadata.labels.app = name;
        spec.containers.${name} = {
          image = config.image;
          ports.http.containerPort = config.port;
        };
      };
    };
    services.${name}.spec = {
      selector.app = name;
      ports.http.port = config.port;
    };
  };
};

# Use the template
applications.frontend.templates.webApp.frontend = {
  image = "frontend:v1.2.3";
  replicas = 5;
};
```

### 🔄 GitOps Ready

Nixidy implements the [Rendered Manifests Pattern](https://akuity.io/blog/the-rendered-manifests-pattern/). Your CI generates plain YAML, you review the exact changes in PRs, and Argo CD deploys them. No surprises.

### 🚀 App-of-Apps Bootstrap

Bootstrap your entire cluster with a single command:

```sh
nixidy bootstrap .#prod | kubectl apply -f -
```

### ⚡ Direct Apply

Skip GitOps if you want to:

```sh
nixidy apply .#dev
```

Uses `kubectl apply --prune` for safe, declarative deployments directly to your cluster.

### 🎛️ CRD Support

Generate typed Nix options from any Custom Resource Definition:

```nix
{ generators, ... }: {
  nixidy.applicationImports = [
    (generators.fromCRDModule {
      name = "cilium";
      src = pkgs.fetchFromGitHub { /* ... */ };
      crdFiles = [
        "pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml"
      ];
    })
  ];
}
```

Then use your CRDs with full type safety:

```nix
resources.ciliumNetworkPolicies.allow-dns.spec = {
  endpointSelector = {};
  egress = [{
    toEndpoints = [{ matchLabels."k8s:io.kubernetes.pod.namespace" = "kube-system"; }];
    toPorts = [{ ports = [{ port = "53"; protocol = "UDP"; }]; }];
  }];
};
```

## Quick Start

### With Flakes

```nix title="flake.nix"
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixidy.url = "github:arnarg/nixidy";
  };

  outputs = { nixpkgs, nixidy, ... }: {
    nixidyEnvs.x86_64-linux = nixidy.lib.mkEnvs {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      envs.dev.modules = [ ./env/dev.nix ];
    };
  };
}
```

```nix title="env/dev.nix"
{
  nixidy.target.repository = "https://github.com/you/your-repo.git";
  nixidy.target.branch = "main";

  applications.hello = {
    namespace = "hello";
    createNamespace = true;
    resources.deployments.hello.spec = {
      selector.matchLabels.app = "hello";
      template = {
        metadata.labels.app = "hello";
        spec.containers.hello.image = "hello-world:latest";
      };
    };
  };
}
```

See the [Getting Started Guide](https://nixidy.dev/user_guide/getting_started/) for detailed setup instructions.

## Documentation

- **[Getting Started](https://nixidy.dev/user_guide/getting_started/)** - Set up your first nixidy project
- **[Helm Charts](https://nixidy.dev/user_guide/helm_charts/)** - Integrate existing Helm charts
- **[Templates](https://nixidy.dev/user_guide/templates/)** - Create reusable application patterns
- **[Git Strategies](https://nixidy.dev/user_guide/git_strategies/)** - Monorepo vs. environment branches
- **[GitHub Actions](https://nixidy.dev/user_guide/github_actions/)** - CI/CD integration
- **[Typed Resources](https://nixidy.dev/user_guide/typed_resources/)** - Generate types for CRDs

## Resources

- **[arnarg/cluster](https://github.com/arnarg/cluster)** - Real-world cluster configuration using nixidy
- **[Introduction to nixidy](https://codedbearder.com/posts/nixidy-part-1-introduction/)** - Tutorial series

## Comparison

| Feature | nixidy | Helm | Kustomize | Raw YAML |
|---------|--------|------|-----------|----------|
| Type Safety | ✅ Full | ❌ None | ❌ None | ❌ None |
| Composability | ✅ Modules | ⚠️ Subcharts | ⚠️ Overlays | ❌ Copy/Paste |
| Helm Integration | ✅ Native | ✅ Native | ⚠️ Inflate | ❌ Manual |
| Reviewable Output | ✅ Plain YAML | ❌ Templates | ⚠️ Patches | ✅ Plain YAML |
| Multi-Environment | ✅ Built-in | ⚠️ Values files | ⚠️ Overlays | ❌ Manual |
| Reproducibility | ✅ Guaranteed | ⚠️ Depends | ⚠️ Depends | ⚠️ Depends |

## Community

- **Issues**: [GitHub Issues](https://github.com/arnarg/nixidy/issues)
- **Discussions**: [GitHub Discussions](https://github.com/arnarg/nixidy/discussions)

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, documentation improvements, or code contributions, please feel free to open an issue or pull request on our [GitHub repository](https://github.com/arnarg/nixidy).

## Acknowledgments

- **[nix-kube-generators](https://github.com/farcaller/nix-kube-generators)** - Used internally for Helm chart rendering
- **[kubenix](https://github.com/hall/kubenix)** - Resource options generator forked from kubenix

## License

nixidy is licensed under the [MIT License](https://github.com/arnarg/nixidy/blob/main/LICENSE).
