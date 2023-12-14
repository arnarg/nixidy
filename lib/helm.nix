{
  lib,
  klib,
  pkgs,
}: {
  /*
  Downloads a helm chart from a helm registry.

  > This is re-exported directly from [farcaller/nix-kube-generators](https://github.com/farcaller/nix-kube-generators).

  Type:
    downloadHelmChart :: AttrSet -> Derivation
  */
  downloadHelmChart = klib.downloadHelmChart;

  /*
  Templates a helm chart with provided values and creates a derivation
  with the output.

  > This is re-exported directly from [farcaller/nix-kube-generators](https://github.com/farcaller/nix-kube-generators).

  Type:
    buildHelmChart :: AttrSet -> Derivation
  */
  buildHelmChart = klib.buildHelmChart;

  /*
  Parse the default values file shipped with the helm chart.

  Type:
    getChartValues :: Derivation -> AttrSet

  Example:
    getChartValues (lib.helm.downloadHelmChart {
        repo = "https://argoproj.github.io/argo-helm/";
        chart = "argo-cd";
        version = "5.51.4";
        chartHash = "sha256-LOEJ5mYaHEA0RztDkgM9DGTA0P5eNd0SzSlwJIgpbWY=";
    })
    => {
      server.replicas = 1;
      controller.replicas = 1;
      # ...
    }
  */
  getChartValues =
    # Derivation containing helm chart. Usually output of [lib.helm.downloadHelmChart](#libhelmdownloadhelmchart).
    chart:
      lib.head (klib.fromYAML (builtins.readFile "${chart}/values.yaml"));

  mkHelmApplication = {
    name,
    namespace,
    chart,
    values ? {},
    extrasGenerator ? _: {},
  }: let
    chartValues = lib.head (klib.fromYAML (builtins.readFile "${chart}/values.yaml"));
    finalValues = lib.attrsets.recursiveUpdate chartValues values;
    extras = extrasGenerator {
      inherit namespace;
      values = finalValues;
    };

    rendered = lib.resources.fromHelmChart {
      inherit chart name namespace values;
    };

    merged = lib.mkMerge [
      rendered
      (extras.resources or {})
      (lib.resources.fromManifestYAMLs (extras.YAMLs or []))
    ];
  in {
    inherit namespace;
    resources = merged;
  };
}
