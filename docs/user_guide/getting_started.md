# Getting Started

This guide walks you through setting up your first nixidy project step by step.

## Prerequisites

- [Nix](https://nixos.org/download.html) installed with flakes enabled
- A Git repository for your Kubernetes manifests
- Basic familiarity with Kubernetes concepts

## What You'll Build

By the end of this guide, you'll have:

1. A nixidy project that generates Kubernetes manifests
2. An nginx deployment with configuration
3. An Argo CD application ready for GitOps

## Step 1: Create Your Project

Create a new directory for your project:

```sh
mkdir my-cluster && cd my-cluster
git init
```

## Step 2: Set Up the Flake

Create a `flake.nix` file in your project root:

```nix title="flake.nix"
{
  description = "My Kubernetes cluster managed with nixidy";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixidy.url = "github:arnarg/nixidy";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    nixidy,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      # Define your environments
      nixidyEnvs = nixidy.lib.mkEnvs {
        inherit pkgs;

        envs = {
          dev.modules = [./env/dev.nix];
        };
      };

      # Make nixidy CLI available
      packages.nixidy = nixidy.packages.${system}.default;

      # Development shell with nixidy
      devShells.default = pkgs.mkShell {
        buildInputs = [nixidy.packages.${system}.default];
      };
    });
}
```

??? note "Using nixidy without flakes"

    If you prefer not to use flakes, you can use [npins](https://github.com/andir/npins) or [niv](https://github.com/nmattia/niv) for dependency management.

    === "npins"

        ```sh
        npins init --bare
        npins add github arnarg nixidy --branch main
        ```

    === "niv"

        ```sh
        niv init --no-nixpkgs
        niv add github arnarg/nixidy --branch main
        ```

    Then create `default.nix`:

    ```nix title="default.nix"
    let
      sources = import ./npins;  # or ./nix/sources.nix for niv
      nixidy = import sources.nixidy {};
    in
      nixidy.lib.mkEnvs {
        envs = {
          dev.modules = [./env/dev.nix];
        };
      }
    ```

    !!! warning "Command syntax"
        The rest of this guide uses flake syntax (e.g., `nixidy build .#dev`). Without flakes, omit the `.#` prefix (e.g., `nixidy build dev`).

## Step 3: Create Your Environment Configuration

Create the environment directory and configuration file:

```sh
mkdir -p env
```

```nix title="env/dev.nix"
{
  # Where should the generated manifests be stored?
  nixidy.target.repository = "https://github.com/YOUR_USERNAME/my-cluster.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/dev";
}
```

!!! tip "Replace the repository URL"
    Change `YOUR_USERNAME` to your actual GitHub username, or use your preferred Git hosting URL.

## Step 4: Verify Your Setup

Enter the development shell and verify everything works:

```sh
nix develop
nixidy info .#dev
```

You should see:

```
Repository: https://github.com/YOUR_USERNAME/my-cluster.git
Branch:     main
```

Try building (it will be empty for now):

```sh
nixidy build .#dev
tree result
```

Output:

```
result
└── apps/
```

The `apps/` folder is empty because we haven't defined any applications yet.

## Step 5: Create Your First Application

Now let's add an nginx application. Update your `env/dev.nix`:

```nix title="env/dev.nix"
{
  # Target configuration
  nixidy.target.repository = "https://github.com/YOUR_USERNAME/my-cluster.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/dev";

  # Define the nginx application
  applications.nginx = {
    # Deploy to the "nginx" namespace
    namespace = "nginx";

    # Automatically create the namespace
    createNamespace = true;

    # Define Kubernetes resources
    resources = {
      # Deployment
      deployments.nginx.spec = {
        replicas = 2;
        selector.matchLabels.app = "nginx";
        template = {
          metadata.labels.app = "nginx";
          spec.containers.nginx = {
            image = "nginx:1.25.1";
            ports.http.containerPort = 80;
          };
        };
      };

      # Service
      services.nginx.spec = {
        selector.app = "nginx";
        ports.http.port = 80;
      };
    };
  };
}
```

## Step 6: Build and Inspect

Build your configuration:

```sh
nixidy build .#dev
tree result
```

You should see:

```
result
├── apps
│   └── Application-nginx.yaml
└── nginx
    ├── Deployment-nginx.yaml
    ├── Namespace-nginx.yaml
    └── Service-nginx.yaml
```

Inspect the generated deployment:

```sh
cat result/nginx/Deployment-nginx.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - image: nginx:1.25.1
          name: nginx
          ports:
            - containerPort: 80
              name: http
```

Nixidy also generates an Argo CD Application:

```sh
cat result/apps/Application-nginx.yaml
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
  namespace: argocd
spec:
  destination:
    namespace: nginx
    server: https://kubernetes.default.svc
  project: default
  source:
    path: ./manifests/dev/nginx
    repoURL: https://github.com/YOUR_USERNAME/my-cluster.git
    targetRevision: main
```

## Step 7: Sync Manifests to Your Repository

Copy the generated manifests to your repository:

```sh
nixidy switch .#dev
```

This creates the `./manifests/dev` directory with all your manifests. Commit and push:

```sh
git add .
git commit -m "Initial nixidy configuration"
git push
```

## Step 8: Deploy to Your Cluster

### Option A: Bootstrap with Argo CD

If you have Argo CD installed, bootstrap all applications with one command:

```sh
nixidy bootstrap .#dev | kubectl apply -f -
```

This creates an "app of apps" that automatically deploys all your applications.

### Option B: Apply Directly

For quick testing without Argo CD:

```sh
nixidy apply .#dev
```

This applies all manifests directly using `kubectl apply --prune`.

## Adding More Resources

Let's extend the nginx application with a ConfigMap:

```nix title="env/dev.nix"
{
  nixidy.target.repository = "https://github.com/YOUR_USERNAME/my-cluster.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/dev";

  applications.nginx = {
    namespace = "nginx";
    createNamespace = true;

    resources = {
      # Deployment with ConfigMap volume
      deployments.nginx.spec = {
        replicas = 2;
        selector.matchLabels.app = "nginx";
        template = {
          metadata.labels.app = "nginx";
          spec = {
            containers.nginx = {
              image = "nginx:1.25.1";
              ports.http.containerPort = 80;
              volumeMounts."/usr/share/nginx/html".name = "html";
            };
            volumes.html.configMap.name = "nginx-html";
          };
        };
      };

      # Service
      services.nginx.spec = {
        selector.app = "nginx";
        ports.http.port = 80;
      };

      # ConfigMap with HTML content
      configMaps.nginx-html.data."index.html" = ''
        <!DOCTYPE html>
        <html>
          <body>
            <h1>Hello from nixidy!</h1>
          </body>
        </html>
      '';
    };
  };
}
```

Build to see the new ConfigMap:

```sh
nixidy build .#dev
cat result/nginx/ConfigMap-nginx-html.yaml
```

## Adding Multiple Applications

You can define multiple applications in the same file or split them into separate modules:

```nix title="env/dev.nix"
{
  nixidy.target.repository = "https://github.com/YOUR_USERNAME/my-cluster.git";
  nixidy.target.branch = "main";
  nixidy.target.rootPath = "./manifests/dev";

  # First application
  applications.nginx = {
    namespace = "nginx";
    createNamespace = true;
    resources.deployments.nginx.spec = {
      selector.matchLabels.app = "nginx";
      template = {
        metadata.labels.app = "nginx";
        spec.containers.nginx.image = "nginx:1.25.1";
      };
    };
  };

  # Second application
  applications.redis = {
    namespace = "redis";
    createNamespace = true;
    resources.deployments.redis.spec = {
      selector.matchLabels.app = "redis";
      template = {
        metadata.labels.app = "redis";
        spec.containers.redis.image = "redis:7";
      };
    };
  };
}
```

## Project Structure

A typical nixidy project looks like this:

```
my-cluster/
├── flake.nix              # Project definition
├── flake.lock             # Locked dependencies
├── env/
│   ├── dev.nix            # Development environment
│   ├── staging.nix        # Staging environment
│   └── prod.nix           # Production environment
├── modules/
│   ├── default.nix        # Common module that imports all applications
│   ├── nginx.nix          # Reusable nginx module
│   └── redis.nix          # Reusable redis module
└── manifests/             # Generated manifests
    ├── dev/
    ├── staging/
    └── prod/
```

## Common Commands

| Command | Description |
|---------|-------------|
| `nixidy info .#dev` | Show environment info |
| `nixidy build .#dev` | Build manifests to `./result` |
| `nixidy switch .#dev` | Sync manifests to target directory |
| `nixidy bootstrap .#dev` | Output bootstrap Application YAML |
| `nixidy apply .#dev` | Apply directly to cluster |

## Troubleshooting

### "nixidy: command not found"

Make sure you're in the development shell:

```sh
nix develop
```

Or run nixidy directly:

```sh
nix run .#nixidy -- build .#dev
```

### Build fails with type errors

Nixidy validates your configuration against Kubernetes schemas. Check the error message for the specific field that's incorrect. Common issues:

- Wrong types (string instead of number)
- Misspelled field names

## Next Steps

Now that you have a working nixidy project, explore these topics:

- **[Helm Charts](./helm_charts.md)** — Use existing Helm charts in your applications
- **[Templates](./templates.md)** — Create reusable application patterns
- **[Git Strategies](./git_strategies.md)** — Organize manifests across branches or repositories
- **[GitHub Actions](./github_actions.md)** — Automate manifest generation in CI
- **[Direct Apply](./direct_apply.md)** — Deploy without Argo CD

## Example Repository

For a complete real-world example, check out [arnarg/cluster](https://github.com/arnarg/cluster).
