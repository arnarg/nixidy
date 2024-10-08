# Using nixhelm

[nixhelm](https://github.com/farcaller/nixhelm) is a collection of Helm Charts that can be used with [nix-kube-generators](https://github.com/farcaller/nixhelm) and as a result also nixidy. The charts are automatically updated to the most recent version by CI regularly.

To use with nixidy, pass the nixhelm derivation attribute set to nixidy's `mkEnv` builder like so.

```nix title="flake.nix"
{
  description = "My ArgoCD configuration with nixidy.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.nixidy = {
    url = "github:arnarg/nixidy";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.nixhelm = {
    url = "github:farcaller/nixhelm";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nixidy,
    nixhelm,
  }: (flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      inherit system;
    };
  in {
    nixidyEnvs.dev = nixidy.lib.mkEnv {
      inherit pkgs;

      # Pass nixhelm to all nixidy modules.
      charts = nixhelm.chartsDerivations.${system};

      modules = [./env/dev.nix];
    };
  }));
}
```

And then the argument `charts` will be passed to every module in nixidy.

```nix title="./env/dev.nix"
{
  lib,
  charts,
  ...
}: {
  applications.traefik = {
    namespace = "traefik";
    createNamespace = true;

    helm.releases.traefik = {
      # Use the traefik helm chart from nixhelm.
      chart = charts.traefik.traefik;

      # Example values to pass to the Helm Chart.
      values = {
        ingressClass.enabled = true;
      };
    };
  };
}
```

## Provide your own charts not available in nixhelm

Not all charts are available in nixhelm and in such cases you can contribute an initial version to them or setup a specific folder structure locally to merge with the `charts` argument passed to modules.

With the nixidy option `nixidy.chartsDir` that folder will be walked recursively and look for `default.nix` files that will build up the charts attribute set.

```nix title="./charts/kubernetes-csi/csi-driver-nfs/default.nix"
{
  repo = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts";
  chart = "csi-driver-nfs";
  version = "4.7.0";
  chartHash = "sha256-EU2qaZglUU3vxa41l1p/2yBscksIhYMr8kSgH8t0vL8=";
}
```

And then in your nixidy modules you pass that `./charts` folder to `nixidy.chartsDir`.

```nix title="./env/dev.nix"
{charts, ...}: {
  # Point nixidy to a directory with charts to add to
  # the charts attribute set.
  nixidy.chartsDir = ../charts;

  # Use the nfs chart in an application.
  applications.csi-driver-nfs = {
    namespace = "kube-system";

    helm.releases.csi-driver-nfs = {
      chart = charts.kubernetes-csi.csi-driver-nfs;

      # Pass some values overrides to the chart.
      values = {};
    };
  };
}
```
