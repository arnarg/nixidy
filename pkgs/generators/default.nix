{
  pkgs,
  kubelib,
  lib ? pkgs.lib,
}:
let
  klib = kubelib.lib { inherit pkgs; };

  #########
  ## K8s ##
  #########
  fromSchema =
    name: schema:
    import ./generator.nix {
      inherit
        pkgs
        lib
        name
        schema
        ;

      # The ports list in Container, EphemeralContainer
      # and ServiceSpec should not enforce "protocol".
      # See: https://github.com/arnarg/nixidy/issues/34
      specialMapKeys = {
        "io.k8s.api.core.v1.Container".ports = [ "containerPort" ];
        "io.k8s.api.core.v1.EphemeralContainer".ports = [ "containerPort" ];
        "io.k8s.api.core.v1.ServiceSpec".ports = [ "port" ];
      };

      definitionsOverlay = final: prev: {
        "io.k8s.apimachinery.pkg.api.resource.Quantity" = {
          inherit (prev."io.k8s.apimachinery.pkg.api.resource.Quantity") description;
          oneOf = [
            { type = "string"; }
            { type = "number"; }
          ];
        };
      };
    };

  genNamespaced =
    core: aggregated:
    let
      core' =
        let
          data = builtins.fromJSON (builtins.readFile core);
        in
        {
          core = {
            ${data.groupVersion} = lib.mergeAttrsList (
              lib.concatMap (
                res:
                lib.optional (res.singularName != "") {
                  ${res.kind} = res.namespaced;
                }
              ) data.resources
            );
          };
        };

      aggregated' =
        let
          data = builtins.fromJSON (builtins.readFile aggregated);
        in
        lib.mergeAttrsList (
          map (item: {
            ${item.metadata.name} = lib.mergeAttrsList (
              map (version: {
                ${version.version} = lib.mergeAttrsList (
                  map (res: {
                    ${res.responseKind.kind} = res.scope == "Namespaced";
                  }) version.resources
                );
              }) item.versions
            );
          }) data.items
        );
    in
    core' // aggregated';

  genRoots =
    with lib;
    swagger: namespaced:
    let
      refType = attr: head (tail (tail (splitString "/" attr."$ref")));

      refDefinition = attr: head (tail (tail (splitString "/" attr."$ref")));

      mapCharPairs =
        f: s1: s2:
        concatStrings (
          imap0 (i: c1: f i c1 (if i >= stringLength s2 then "" else elemAt (stringToCharacters s2) i)) (
            stringToCharacters s1
          )
        );

      getAttrName =
        resource: kind:
        mapCharPairs (
          i: c1: c2:
          if lib.hasPrefix "API" kind && i == 0 then
            "A"
          else if i == 0 then
            c1
          else if c2 == "" || (lib.toLower c2) != c1 then
            c1
          else
            c2
        ) resource kind;
    in
    mapAttrs'
      (
        name: path:
        let
          ref = refType (head path.post.parameters).schema;
          name' = last (splitString "/" name);
          group' = path.post."x-kubernetes-group-version-kind".group;
          group = if group' == "" then "core" else group';
          version = path.post."x-kubernetes-group-version-kind".version;
          kind = path.post."x-kubernetes-group-version-kind".kind;
          attrName = getAttrName name' kind;
        in
        nameValuePair ref {
          inherit
            ref
            attrName
            group
            version
            kind
            ;
          inherit (swagger.definitions.${ref}) description;

          name = name';
          definition = refDefinition (head path.post.parameters).schema;
          namespaced = attrByPath [ group version kind ] false namespaced;
        }
      )
      (
        filterAttrs (
          _name: path: hasAttr "post" path && path.post."x-kubernetes-action" == "post"
        ) swagger.paths
      );

  k8s = pkgs.linkFarm "k8s-generated" (
    builtins.attrValues (
      builtins.mapAttrs (
        version: conf:
        let
          short = builtins.concatStringsSep "." (lib.lists.sublist 0 2 (builtins.splitVersion version));

          src = pkgs.fetchFromGitHub {
            owner = "kubernetes";
            repo = "kubernetes";
            rev = "v${version}";
            hash = conf.hash;
          };

          namespaced = genNamespaced "${src}/${conf.discovery.core}" "${src}/${conf.discovery.aggregated}";

          swagger = builtins.fromJSON (builtins.readFile "${src}/${conf.spec}");

          schema = {
            inherit (swagger) definitions;
            roots = genRoots swagger namespaced;
          };
        in
        {
          name = "v${short}.nix";
          path = fromSchema "v${short}" schema;
        }
      ) (import ./versions.nix)
    )
  );

  #########
  ## CRD ##
  #########
  # Run the CRD YAML through crd2jsonschema.py and read the resulting JSON
  # schema back into Nix.
  #
  # The nix code generator is slightly modified from kubenix's generator. As
  # it kind of depends on the jsonschema to be flattened with `$ref`s we first
  # pre-process the CRD with a crude python script to flatten it before running
  # the generator. See: crd2jsonschema.py
  #
  # This Python parse is the one unavoidable IFD; both the file generator
  # (`fromCRD`) and the native module generator (`fromCRDModule`) share it.
  crdSchema =
    {
      name,
      src,
      crds,
      namePrefix ? "",
      attrNameOverrides ? { },
      # Optional list of CRD `kind` names to generate. When empty (the
      # default) every CustomResourceDefinition found in `crds` is generated.
      # Useful when `crds` points at a multi-document stream (e.g. raw
      # `helm template` output) containing more kinds than you want.
      kindFilter ? [ ],
    }:
    let
      options = pkgs.writeText "${name}-crd2jsonschema-options.json" (
        builtins.toJSON {
          inherit
            crds
            namePrefix
            attrNameOverrides
            kindFilter
            ;
        }
      );

      pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
    in
    builtins.fromJSON (
      builtins.readFile (
        pkgs.stdenv.mkDerivation {
          inherit src;

          name = "${name}-jsonschema.json";

          phases = [
            "unpackPhase"
            "installPhase"
          ];

          installPhase = ''
            ${pythonWithYaml}/bin/python ${./crd2jsonschema.py} "${options}" > $out
          '';
        }
      )
    );

  fromCRD =
    {
      name,
      src,
      crds,
      namePrefix ? "",
      attrNameOverrides ? { },
      skipCoerceToList ? { },
      kindFilter ? [ ],
    }:
    import ./generator.nix {
      inherit
        pkgs
        lib
        name
        skipCoerceToList
        ;

      schema = crdSchema {
        inherit
          name
          src
          crds
          namePrefix
          attrNameOverrides
          kindFilter
          ;
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
      crds,
      namePrefix ? "",
      attrNameOverrides ? { },
      skipCoerceToList ? { },
      specialMapKeys ? { },
      kindFilter ? [ ],
    }:
    import ./module.nix {
      inherit
        lib
        name
        skipCoerceToList
        specialMapKeys
        ;

      schema = crdSchema {
        inherit
          name
          src
          crds
          namePrefix
          attrNameOverrides
          kindFilter
          ;
      };
    };

  # Extract the raw CustomResourceDefinition objects from a set of CRD YAML
  # files. The objects counterpart to `fromCRD`: same `src`/`crds` inputs, but
  # returns the CRD manifests as values (e.g. to apply them to a cluster)
  # instead of generating resource option modules. Deployment-agnostic — what
  # you do with the objects is up to you.
  #
  # `kindFilter`, when non-empty, keeps only CRDs whose `spec.names.kind` is in
  # the list (mirrors `fromCRD`'s `kindFilter` and `fromChartCRD`'s `crds`).
  crdObjects =
    {
      src,
      crds,
      kindFilter ? [ ],
    }:
    let
      objects = lib.concatMap (f: klib.fromYAML (builtins.readFile "${src}/${f}")) crds;

      isWanted =
        obj:
        obj != null
        && obj ? kind
        && obj.kind == "CustomResourceDefinition"
        && (kindFilter == [ ] || lib.any (x: obj.spec.names.kind == x) kindFilter);
    in
    lib.filter isWanted objects;

  fromChartCRD =
    {
      name,
      chartAttrs ? { },
      chart ? null,
      values ? { },
      crds ? [ ],
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
        && (crds == [ ] || (lib.any (x: obj.spec.names.kind == x) crds));

      filtered = lib.filter isWanted objects;

      src = pkgs.stdenv.mkDerivation {
        yamlText = pkgs.lib.strings.concatStringsSep "\n---\n" (map builtins.toJSON filtered);
        passAsFile = "yamlText";
        name = "toYAMLFile";
        phases = [ "buildPhase" ];
        buildPhase = ''
          mkdir $out
          ${pkgs.yq-go}/bin/yq -P -M $yamlTextPath > $out/crds.yaml
        '';
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

      crds = [
        "crds.yaml"
      ];
    };

  # Template a chart's CRDs to a raw `crds.yaml` derivation (helm template
  # --include-crds). Shared by the chart-based module/object accessors so the
  # chart is templated once; calling both with identical args reuses this one
  # derivation. Unlike `fromChartCRD`, the output is the raw helm YAML (no
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
    in
    pkgs.stdenv.mkDerivation {
      name = "chart-crds-${name}";

      passAsFile = [ "helmValues" ];
      helmValues = builtins.toJSON values;

      allowSubstitutes = false;
      preferLocalBuild = true;

      phases = [ "installPhase" ];
      installPhase = ''
        export HELM_CACHE_HOME="$TMP/.nix-helm-build-cache"
        mkdir -p $out

        ${pkgs.kubernetes-helm}/bin/helm template \
        --include-crds \
        --kube-version "${kubeVersion}" \
        --values "$helmValuesPath" \
        "${name}" \
        "${_chart}" \
        ${builtins.concatStringsSep " " extraOpts} \
        > $out/crds.yaml
      '';
    };

  # Chart counterpart to `fromCRDModule`: template a chart's CRDs and return a
  # module value (resource type options). `crds`, when non-empty, narrows the
  # generated types to those CRD kinds (mirrors `fromChartCRD`).
  fromChartCRDModule =
    {
      name,
      chart ? null,
      chartAttrs ? { },
      values ? { },
      crds ? [ ],
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
      src = mkChartCRDsYaml {
        inherit
          name
          chart
          chartAttrs
          values
          extraOpts
          kubeVersion
          ;
      };
      crds = [ "crds.yaml" ];
      kindFilter = crds;
    };

  # Chart counterpart to `crdObjects`: template a chart's CRDs and return the
  # raw CustomResourceDefinition manifests as values. `crds` empty = every CRD.
  crdObjectsFromChart =
    {
      name,
      chart ? null,
      chartAttrs ? { },
      values ? { },
      crds ? [ ],
      extraOpts ? [ ],
      kubeVersion ? "v${pkgs.kubernetes.version}",
    }:
    crdObjects {
      src = mkChartCRDsYaml {
        inherit
          name
          chart
          chartAttrs
          values
          extraOpts
          kubeVersion
          ;
      };
      crds = [ "crds.yaml" ];
      kindFilter = crds;
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
    crds = [
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
