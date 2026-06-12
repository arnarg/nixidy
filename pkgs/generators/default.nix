{
  pkgs,
  kubelib,
  lib ? pkgs.lib,
}:
let
  klib = kubelib.lib { inherit pkgs; };

  crdSrc = import ./sources/crd.nix { inherit pkgs lib klib; };
  chartSrc = import ./sources/chart.nix { inherit pkgs lib klib; };
  k8sSrc = import ./sources/k8s.nix { inherit pkgs lib; };

  #########
  ## K8s ##
  #########
  k8s = pkgs.linkFarm "k8s-generated" (
    map (v: {
      name = "v${v.short}.nix";
      path = import ./compile/generator.nix {
        inherit pkgs lib;
        name = "v${v.short}";
        schema = v.schema;
        inherit (k8sSrc.k8sCompileOptions) specialMapKeys definitionsOverlay;
      };
    }) k8sSrc.perVersion
  );

  #########
  ## CRD ##
  #########
  # Resolve a renamed argument: prefer the new name, fall back to the
  # deprecated `crds` alias (emitting a warning that points at the new name),
  # else the supplied default. `default` is only forced when neither is given,
  # so passing a `throw` makes the new argument effectively required.
  renamedArg =
    {
      fn,
      old ? "crds",
      new,
      newVal,
      oldVal,
      default,
    }:
    if newVal != null then
      lib.warnIf (
        oldVal != null
      ) "${fn}: both `${old}` and `${new}` given; ignoring deprecated `${old}`" newVal
    else if oldVal != null then
      lib.warn "${fn}: argument `${old}` is deprecated, use `${new}` instead" oldVal
    else
      default;

  fromCRD =
    {
      name,
      src,
      # List of CRD YAML files (relative to `src`) to generate types from.
      crdFiles ? null,
      # Deprecated alias for `crdFiles`.
      crds ? null,
      namePrefix ? "",
      attrNameOverrides ? { },
      skipCoerceToList ? { },
      kindFilter ? [ ],
    }:
    import ./compile/generator.nix {
      inherit
        pkgs
        lib
        name
        skipCoerceToList
        ;

      schema = crdSrc.crdSchema {
        inherit
          name
          src
          namePrefix
          attrNameOverrides
          kindFilter
          ;
        crdFiles = renamedArg {
          fn = "fromCRD";
          new = "crdFiles";
          newVal = crdFiles;
          oldVal = crds;
          default = throw "fromCRD: `crdFiles` is required";
        };
      };
    };

  # Like `fromCRD`, but returns the resource definitions as a module *value*
  # (a `{ lib, options, config, ... }: { ... }` function) instead of a
  # derivation that builds a `.nix` file. This removes the
  # generate-source-then-`import` round-trip — the result can be placed
  # directly in `nixidy.applicationImports`, which already accepts
  # `functionTo attrs`.
  fromCRDModule =
    {
      name,
      src,
      # List of CRD YAML files (relative to `src`) to generate types from.
      crdFiles ? null,
      # Deprecated alias for `crdFiles`.
      crds ? null,
      namePrefix ? "",
      attrNameOverrides ? { },
      skipCoerceToList ? { },
      specialMapKeys ? { },
      kindFilter ? [ ],
    }:
    import ./compile/module.nix {
      inherit
        lib
        name
        skipCoerceToList
        specialMapKeys
        ;

      schema = crdSrc.crdSchema {
        inherit
          name
          src
          namePrefix
          attrNameOverrides
          kindFilter
          ;
        crdFiles = renamedArg {
          fn = "fromCRDModule";
          new = "crdFiles";
          newVal = crdFiles;
          oldVal = crds;
          default = throw "fromCRDModule: `crdFiles` is required";
        };
      };
    };

  # Extract the raw CustomResourceDefinition objects from a set of CRD YAML
  # files. The objects counterpart to `fromCRD`: same `src`/`crdFiles` inputs,
  # but returns the CRD manifests as values (e.g. to apply them to a cluster)
  # instead of generating resource option modules. Deployment-agnostic — what
  # you do with the objects is up to you.
  #
  # `kindFilter`, when non-empty, keeps only CRDs whose `spec.names.kind` is in
  # the list (mirrors `fromCRD`'s and `fromChartCRD`'s `kindFilter`).
  crdObjects =
    {
      src,
      # List of CRD YAML files (relative to `src`) to read.
      crdFiles ? null,
      # Deprecated alias for `crdFiles`.
      crds ? null,
      kindFilter ? [ ],
    }:
    crdSrc.crdObjects {
      inherit src kindFilter;
      crdFiles = renamedArg {
        fn = "crdObjects";
        new = "crdFiles";
        newVal = crdFiles;
        oldVal = crds;
        default = throw "crdObjects: `crdFiles` is required";
      };
    };

  fromChartCRD =
    {
      name,
      chartAttrs ? { },
      chart ? null,
      values ? { },
      # Optional list of CRD `kind` names to keep. Empty/unset = every CRD.
      kindFilter ? null,
      # Deprecated alias for `kindFilter`.
      crds ? null,
      namePrefix ? "",
      attrNameOverrides ? { },
      skipCoerceToList ? { },
      extraOpts ? [ ],
      # Kubernetes version to template the chart against (`helm template
      # --kube-version`). Defaults to the version in nixidy's nixpkgs; override
      # to match the cluster the CRDs are destined for.
      kubeVersion ? "v${pkgs.kubernetes.version}",
    }:
    let
      kindFilter' = renamedArg {
        fn = "fromChartCRD";
        new = "kindFilter";
        newVal = kindFilter;
        oldVal = crds;
        default = [ ];
      };

      src = chartSrc.mkChartCRDFileSrc {
        inherit
          name
          chart
          chartAttrs
          values
          extraOpts
          kubeVersion
          ;
        kindFilter = kindFilter';
      };
    in
    fromCRD {
      inherit
        name
        src
        namePrefix
        attrNameOverrides
        skipCoerceToList
        ;

      crdFiles = [
        "crds.yaml"
      ];
    };

  # Chart counterpart to `fromCRDModule`: template a chart's CRDs and return a
  # module value (resource type options). `kindFilter`, when non-empty, narrows
  # the generated types to those CRD kinds (mirrors `fromChartCRD`).
  fromChartCRDModule =
    {
      name,
      chart ? null,
      chartAttrs ? { },
      values ? { },
      # Optional list of CRD `kind` names to keep. Empty/unset = every CRD.
      kindFilter ? null,
      # Deprecated alias for `kindFilter`.
      crds ? null,
      extraOpts ? [ ],
      kubeVersion ? "v${pkgs.kubernetes.version}",
      namePrefix ? "",
      attrNameOverrides ? { },
      skipCoerceToList ? { },
    }:
    fromCRDModule {
      inherit
        name
        namePrefix
        attrNameOverrides
        skipCoerceToList
        ;
      src = chartSrc.mkChartCRDsYaml {
        inherit
          name
          chart
          chartAttrs
          values
          extraOpts
          kubeVersion
          ;
      };
      crdFiles = [ "crds.yaml" ];
      kindFilter = renamedArg {
        fn = "fromChartCRDModule";
        new = "kindFilter";
        newVal = kindFilter;
        oldVal = crds;
        default = [ ];
      };
    };

  # Chart counterpart to `crdObjects`: template a chart's CRDs and return the
  # raw CustomResourceDefinition manifests as values. `kindFilter` empty = every
  # CRD.
  crdObjectsFromChart =
    {
      name,
      chart ? null,
      chartAttrs ? { },
      values ? { },
      # Optional list of CRD `kind` names to keep. Empty/unset = every CRD.
      kindFilter ? null,
      # Deprecated alias for `kindFilter`.
      crds ? null,
      extraOpts ? [ ],
      kubeVersion ? "v${pkgs.kubernetes.version}",
    }:
    crdObjects {
      src = chartSrc.mkChartCRDsYaml {
        inherit
          name
          chart
          chartAttrs
          values
          extraOpts
          kubeVersion
          ;
      };
      crdFiles = [ "crds.yaml" ];
      kindFilter = renamedArg {
        fn = "crdObjectsFromChart";
        new = "kindFilter";
        newVal = kindFilter;
        oldVal = crds;
        default = [ ];
      };
    };
in
{
  inherit
    fromCRD
    fromCRDModule
    fromChartCRD
    fromChartCRDModule
    crdObjects
    crdObjectsFromChart
    k8s
    ;

  argocd = fromCRD {
    name = "argocd";
    src = pkgs.fetchFromGitHub {
      owner = "argoproj";
      repo = "argo-cd";
      rev = "v3.0.0";
      hash = "sha256-g401mpNEhCNe8H6lk2HToAEZlZa16Py8ozK2z5/UozA=";
    };
    crdFiles = [
      "manifests/crds/application-crd.yaml"
      "manifests/crds/applicationset-crd.yaml"
      "manifests/crds/appproject-crd.yaml"
    ];
    skipCoerceToList = {
      # Coercing AppProject.spec.destinations from attrset
      # to list based on `name` doesn't make sense.
      # See: https://github.com/arnarg/nixidy/issues/60
      "argoproj.io.v1alpha1.AppProjectSpec" = [ "destinations" ];
    };
  };
}
