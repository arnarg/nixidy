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
}
