{
  pkgs,
  lib,
  klib,
}:
let
  # Template a chart's CRDs into a `crds.yaml` derivation by re-serializing the
  # filtered CRD objects. This is the chart acquisition for the *file* generator
  # (`fromChartCRD`): `klib.fromHelm` -> filter CustomResourceDefinitions ->
  # re-serialize via `yq`. Distinct from `mkChartCRDsYaml`, which copies the raw
  # `buildHelmChart` output verbatim.
  mkChartCRDFileSrc =
    {
      name,
      chart ? null,
      chartAttrs ? { },
      values ? { },
      kindFilter ? [ ],
      extraOpts ? [ ],
      kubeVersion ? "v${pkgs.kubernetes.version}",
    }:
    let
      _chart = if chart != null then chart else klib.downloadHelmChart chartAttrs;

      objects = klib.fromHelm {
        inherit
          name
          values
          extraOpts
          kubeVersion
          ;
        includeCRDs = true;
        chart = _chart;
      };

      isWanted =
        obj:
        obj ? kind
        && obj.kind == "CustomResourceDefinition"
        && (kindFilter == [ ] || (lib.any (x: obj.spec.names.kind == x) kindFilter));

      filtered = lib.filter isWanted objects;
    in
    pkgs.stdenv.mkDerivation {
      yamlText = lib.concatStringsSep "\n---\n" (map builtins.toJSON filtered);
      passAsFile = "yamlText";
      name = "chart-crd-file-${name}";
      phases = [ "buildPhase" ];
      buildPhase = ''
        mkdir $out
        ${pkgs.yq-go}/bin/yq -P -M $yamlTextPath > $out/crds.yaml
      '';
    };

  # Template a chart's CRDs to a raw `crds.yaml` derivation (helm template
  # --include-crds). Shared by the chart-based module/object accessors so the
  # chart is templated once; calling both with identical args reuses this one
  # derivation. Unlike `mkChartCRDFileSrc`, the output is the raw helm YAML (no
  # re-serialization), which the downstream accessors parse directly.
  mkChartCRDsYaml =
    {
      name,
      chart ? null,
      chartAttrs ? { },
      values ? { },
      extraOpts ? [ ],
      kubeVersion ? "v${pkgs.kubernetes.version}",
    }:
    let
      _chart = if chart != null then chart else klib.downloadHelmChart chartAttrs;

      templated = klib.buildHelmChart {
        inherit
          name
          values
          extraOpts
          kubeVersion
          ;
        chart = _chart;
        includeCRDs = true;
      };
    in
    # `buildHelmChart` emits a single YAML *file*; copy (not symlink) it into a
    # directory `$out/crds.yaml`. `crdObjects` reads this at eval time via
    # `readFile "${src}/crds.yaml"`, and a `linkFarm` symlink would make that
    # read follow into a separate derivation output not carried in the string's
    # context — forbidden in pure eval. A real file keeps the read in-context.
    pkgs.runCommand "chart-crds-${name}" { } ''
      mkdir -p $out
      cp ${templated} $out/crds.yaml
    '';
in
{
  inherit
    mkChartCRDFileSrc
    mkChartCRDsYaml
    ;
}
