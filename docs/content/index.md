---
title: Kubernetes GitOps with Nix and Argo CD
description: "nixidy lets you describe everything running in your Kubernetes clusters with Nix and the NixOS module system. It renders your configuration to plain YAML manifests, which you commit to a Git repository for Argo CD to deploy."
nav:
  section: user-guide
  order: 0
  label: Introduction
---

## Why nixidy?

Kubernetes configuration tends to sprawl. Helm charts need ever-growing value overrides, Kustomize overlays repeat themselves, and raw YAML is copied between environments until nobody knows which copy is right. Reviewing what a change actually does to a cluster is hard.

nixidy brings the tools NixOS uses to manage a whole operating system to Kubernetes:

- **One language for everything.** Your own resources, Helm charts and Kustomize applications are configured in the same place, with the same module system.
- **Typed resources.** Every Kubernetes resource, and the CRDs you generate options for, is checked when you build, before anything reaches a cluster.
- **Reusable modules.** Share a base configuration between environments and override only what differs.
- **Reviewable output.** Every change is a diff of plain YAML in a pull request, so you see exactly what [Argo CD](https://argo-cd.readthedocs.io/) will apply.
- **Reproducible builds.** Charts and sources are pinned, so the same configuration always renders the same manifests.

## How It Works

Describe an application with Nix:

```nix title="env/prod.nix"
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

Build the environment:

```sh
nixidy build .#prod
```

And get plain manifests, including an Argo CD `Application` for each application:

```
result/
├── apps/
│   └── Application-demo.yaml
└── demo/
    ├── Deployment-nginx.yaml
    ├── Namespace-demo.yaml
    └── Service-nginx.yaml
```

Commit the manifests to your repository and Argo CD deploys them. This is the [rendered manifests pattern](https://akuity.io/blog/the-rendered-manifests-pattern/): what's in Git is exactly what runs in the cluster.

## Explore the Guides

/// define
[Getting Started](user_guide/getting_started.md)

- Set up a project with a flake, define your first environment and bootstrap Argo CD.

[Helm Charts](user_guide/helm_charts.md)

- Render Helm charts as part of an application and patch the resources they produce. [nixhelm](user_guide/using_nixhelm.md) provides a large collection of charts ready to use.

[Typed Resources](user_guide/typed_resources.md)

- Use the typed options for Kubernetes resources, include existing YAML, and generate options from any CRD.

[Templates](user_guide/templates.md)

- Package common patterns, such as a deployment with a service, into templates with their own options.

[Git Strategies](user_guide/git_strategies.md)

- Keep environments in a single repository, in separate branches or in separate repositories.

[GitHub Actions](user_guide/github_actions.md)

- Build environments and push the rendered manifests from CI.

[Transformers](user_guide/transformers.md), [Object Transforms](user_guide/object_transforms.md) and [Post-processing](user_guide/postprocessing.md)

- Modify resources from any source, such as Helm charts, before they're written, and process the rendered files.

[Directly Apply Manifests](user_guide/direct_apply.md)

- Skip GitOps and apply an environment to a cluster with `nixidy apply`.

[Assertions & Warnings](user_guide/assertions.md)

- Validate your configuration at build time, including references between resources.
///

The reference documents the [command line interface](cli_reference.md), the [library functions](library.md) and every [configuration option](options.md).

## Learn More

- [arnarg/cluster](https://github.com/arnarg/cluster) is a real-world cluster configured with nixidy.
- [Introduction to nixidy](https://codedbearder.com/posts/nixidy-part-1-introduction/) is a tutorial series about nixidy.
- Questions and ideas are welcome in [GitHub Discussions](https://github.com/arnarg/nixidy/discussions), and bugs in [GitHub Issues](https://github.com/arnarg/nixidy/issues).
- Interested in contributing? The [architecture guide](developer_guide/architecture.md) explains how nixidy works internally.
