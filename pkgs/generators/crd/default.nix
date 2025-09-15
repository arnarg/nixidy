{
  pkgs,
  lib,
  name,
  src,
  crds,
  namePrefix,
  attrNameOverrides,
}:
let
  options = pkgs.writeText "${name}-crd2jsonschema-options.json" (
    builtins.toJSON {
      inherit crds namePrefix attrNameOverrides;
    }
  );

  # The nix code generator is slightly modified from kubenix's
  # generator. As it kind of depends on the jsonschema to be
  # flattened with `$ref`s we first pre-process the CRD with
  # a crude python script to flatten it before running the
  # generator.
  # See: crd2jsonschema.py
  schema =
    let
      pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
    in
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
    };
in
import ./jsonschema.nix {
  inherit name pkgs lib;
  spec = schema;
}
