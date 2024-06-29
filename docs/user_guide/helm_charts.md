# Using Helm Charts

For better or for worse majority of software that's deployable to Kubernetes is packaged using Helm by developers or its community. It would be a waste not to use them and having to define all of its manifest yourself in nixidy.

## Adding a Helm release as part of an application

Nixidy supports rendering Helm charts as part of applications. This can be done by specifying `applications.<applicationName>.helm.releases.<releaseName>`.

### Example

```nix
{lib, ...}: {
  applications.traefik = {
    namespace = "traefik";
    createNamespace = true;

    helm.releases.traefik = {
      # Use `lib.helm.downloadHelmChart` to fetch
      # the Helm Chart to use.
      chart = lib.helm.downloadHelmChart {
        repo = "https://traefik.github.io/charts/";
        chart = "traefik";
        version = "25.0.0";
        chartHash = "sha256-ua8KnUB6MxY7APqrrzaKKSOLwSjDYkk9tfVkb1bqkVM=";
      };

      # Example values to pass to the Helm Chart.
      values = {
        ingressClass.enabled = true;
      };
    };
  };
}
```


## Patching manifests rendered by Helm

In some cases the Helm Chart doesn't support changing certain aspects of the final manifests. These can be modified to nixidy by overriding certain fields.

### Example

```nix
{lib, ...}: {
  applications.traefik = {
    namespace = "traefik";
    createNamespace = true;

    helm.releases.traefik = {
      # Use `lib.helm.downloadHelmChart` to fetch
      # the Helm Chart to use.
      chart = lib.helm.downloadHelmChart {
        repo = "https://traefik.github.io/charts/";
        chart = "traefik";
        version = "25.0.0";
        chartHash = "sha256-ua8KnUB6MxY7APqrrzaKKSOLwSjDYkk9tfVkb1bqkVM=";
      };

      # Example values to pass to the Helm Chart.
      values = {
        ingressClass.enabled = true;
      };
    };

    resources = {
      # Add a label to the traefik pod and change
      # the image.
      deployments.traefik.spec.template = {
        metadata.labels.my-custom-label = "my-custom-values";
        spec.containers.traefik.image = "my-registry.io/patched-traefik:v3.0.0";
      };
    };
  };
}
```
