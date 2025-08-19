# Directly Apply Manifests

The `nixidy apply` sub-command provides a way to directly apply the manifests to a Kubernetes cluster. This is an alternative to using a GitOps controller like Argo CD.

## How it works

When you run `nixidy apply`, it builds a nix package that contains all your Kubernetes manifests. These manifests are grouped into three categories and applied in the following order:

1.  **Custom Resource Definitions (CRDs)**: CRDs are applied first to ensure that any custom resources are known to the cluster before the manifests that use them are applied.
2.  **Namespaces**: Namespaces are applied next to ensure that all required namespaces exist before any namespaced resources are created.
3.  **Other manifests**: All other manifests, such as Deployments, Services, and ConfigMaps, are applied last.

It uses `kubectl apply --prune` to apply the manifests. The `--prune` flag is used to remove any resources from the cluster that are no longer defined in your nixidy configuration. Specific labels are added to all resources to make pruning safe and effective.

## Usage

To apply the manifests for a specific environment, you can run:

```sh
nixidy apply .#dev
```

This will build the manifests for the `dev` environment and apply them to the currently configured Kubernetes cluster.

!!! info
    Make sure to set `#!nix createNamespace = true;` in all nixidy applications using namespaces that do not already exist in your Kubernetes cluster.
