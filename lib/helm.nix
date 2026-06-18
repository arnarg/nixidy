{
  lib,
  klib,
  pkgs,
}:
{
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
    chart: lib.head (klib.fromYAML (builtins.readFile "${chart}/values.yaml"));

  /*
    Walk a directory tree and import all `default.nix` to download helm charts.

    The `default.nix` needs to have the following format:

    ```nix title="./charts/kubernetes-csi/csi-driver-nfs/default.nix"
    {
      repo = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts";
      chart = "csi-driver-nfs";
      version = "4.7.0";
      chartHash = "sha256-EU2qaZglUU3vxa41l1p/2yBscksIhYMr8kSgH8t0vL8=";
    }
    ```

    Type:
      mkChartAttrs :: Path -> AttrSet

    Example:
      mkChartAttrs ./charts
      => {
        kubernetes-csi = {
          csi-driver-nfs = lib.helm.downloadHelmChart {
            repo = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts";
            chart = "csi-driver-nfs";
            version = "4.7.0";
            chartHash = "sha256-EU2qaZglUU3vxa41l1p/2yBscksIhYMr8kSgH8t0vL8=";
          };
        };
      }
  */
  mkChartAttrs =
    # Path to a directory containing the correct directory structure described above.
    rootDir:
    let
      effectiveRoot =
        let
          d = toString rootDir;
        in
        if lib.hasPrefix "/nix/store/" d then
          let
            stripped = lib.pipe d [
              (lib.removePrefix "/nix/store/")
              (lib.splitString "/")
              (lib.drop 1)
              (lib.concatStringsSep "/")
            ];
          in
          # empty => rootDir was copied as a standalone store entry; can't infer runtime path
          if stripped == "" then null else "./${stripped}"
        else
          d;

      updateChartScript = pkgs.writeScriptBin "update-chart" (
        builtins.readFile ./helpers/update-chart.sh
      );

      walkDir =
        prefix: dir: relPath:
        let
          contents = builtins.readDir "${prefix}/${dir}";
          chartDir = "${prefix}/${dir}";

          mkChart =
            let
              attrs = import chartDir;
            in
            (lib.helm.downloadHelmChart (lib.getAttrs [ "repo" "chart" "version" "chartHash" ] attrs))
            .overrideAttrs
              (_: {
                passthru = {
                  inherit (attrs)
                    repo
                    chart
                    version
                    chartHash
                    ;
                  updateScript = pkgs.writeShellScriptBin "update-chart-${attrs.chart}" ''
                    set -euo pipefail

                    export PATH="${
                      lib.makeBinPath [
                        pkgs.kubernetes-helm
                        pkgs.yq-go
                        pkgs.gnused
                      ]
                    }:$PATH"

                    export CHART_REPO=${lib.escapeShellArg attrs.repo}
                    export CHART_NAME=${lib.escapeShellArg attrs.chart}
                    export CHART_SUBPATH=${lib.escapeShellArg relPath}
                    export CHART_VERSION_CONSTRAINT=${lib.escapeShellArg (attrs.versionConstraint or "")}

                    ${
                      if effectiveRoot == null then
                        ''
                          # rootDir was copied as a standalone store entry and path can't
                          # be inferred.
                          # Require CHARTS_DIR at runtime and fail loudly if unset.
                          : "''${CHARTS_DIR:?CHARTS_DIR must be set at runtime (rootDir was copied as a standalone store entry)}"
                        ''
                      else
                        ''
                          # charts root is runtime-relative (working tree), NOT the store path
                          export CHARTS_DIR="''${CHARTS_DIR:-${effectiveRoot}}"
                        ''
                    }

                    ${updateChartScript}/bin/update-chart
                  '';
                };
              });
        in
        if contents ? "default.nix" && contents."default.nix" == "regular" then
          mkChart
        else
          builtins.listToAttrs (
            map (d: {
              inherit (d) name;
              value = walkDir chartDir d.name "${relPath}/${d.name}";
            }) (lib.filter (c: c.value == "directory") (lib.attrsToList contents))
          );

      tree = builtins.listToAttrs (
        map (d: {
          inherit (d) name;
          value = walkDir rootDir d.name d.name;
        }) (lib.filter (c: c.value == "directory") (lib.attrsToList (builtins.readDir rootDir)))
      );
    in
    tree;

  /*
    Build a single shell script that runs every chart's `updateScript`
    sequentially. The script keeps going when an individual chart fails and
    exits non-zero at the end if any chart failed.

    Type:
      mkChartsUpdateScript :: AttrSet -> Derivation

    Example:
      mkChartsUpdateScript (mkChartAttrs ./charts)
      => <derivation update-all-charts>
  */
  mkChartsUpdateScript =
    # Tree of helm chart derivations, as produced by [lib.helm.mkChartAttrs](#libhelmmkchartattrs).
    tree:
    let
      # Walks a tree and collects derivations carrying `passthru.updateScript`.
      # Stops at derivations so it does not recurse into `passthru`.
      collectChartLeafs =
        let
          go =
            path: v:
            if lib.isDerivation v then
              (
                if v ? passthru && v.passthru ? updateScript then
                  [
                    {
                      path = lib.concatStringsSep "/" path;
                      inherit (v.passthru) chart updateScript;
                    }
                  ]
                else
                  [ ]
              )
            else if lib.isAttrs v then
              lib.concatLists (lib.mapAttrsToList (k: c: go (path ++ [ k ]) c) v)
            else
              [ ];
        in
        go [ ];

      leafs = collectChartLeafs tree;
    in
    pkgs.writeShellScriptBin "update-all-charts" ''
      set -uo pipefail

      failed=0
      ${lib.concatMapStringsSep "\n" (l: ''
        echo "checking ${l.chart} (${l.path})..."
        if ${lib.getExe l.updateScript}; then
          echo ""
        else
          echo "FAILED: ${l.chart}\n" >&2
          failed=1
        fi
      '') leafs}

      if [ "$failed" -ne 0 ]; then
        echo "One or more charts failed to update" >&2
        exit 1
      fi
      echo "Done"
    '';
}
