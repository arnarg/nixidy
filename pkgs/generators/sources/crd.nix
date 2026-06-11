{
  pkgs,
  lib,
  klib,
}:
let
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
      crdFiles,
      namePrefix ? "",
      attrNameOverrides ? { },
      # Optional list of CRD `kind` names to generate. When empty (the
      # default) every CustomResourceDefinition found in `crdFiles` is
      # generated. Useful when `crdFiles` points at a multi-document stream
      # (e.g. raw `helm template` output) containing more kinds than you want.
      kindFilter ? [ ],
    }:
    let
      options = pkgs.writeText "${name}-crd2jsonschema-options.json" (
        builtins.toJSON {
          # crd2jsonschema.py reads this under the JSON key `crds`.
          crds = crdFiles;
          inherit
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
            ${pythonWithYaml}/bin/python ${../crd2jsonschema.py} "${options}" > $out
          '';
        }
      )
    );

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
      crdFiles,
      kindFilter ? [ ],
    }:
    let
      objects = lib.concatMap (f: klib.fromYAML (builtins.readFile "${src}/${f}")) crdFiles;

      isWanted =
        obj:
        obj != null
        && obj ? kind
        && obj.kind == "CustomResourceDefinition"
        && (kindFilter == [ ] || lib.any (x: obj.spec.names.kind == x) kindFilter);
    in
    lib.filter isWanted objects;
in
{
  inherit
    crdSchema
    crdObjects
    ;
}
