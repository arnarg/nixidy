{
  pkgs,
  lib,
  name,
  src,
  crds,
}: let
  schema = let
    pythonWithYaml = pkgs.python3.withPackages (ps: [ps.pyyaml]);
  in
    pkgs.stdenv.mkDerivation {
      inherit src;

      name = "${name}-jsonschema.json";

      phases = ["unpackPhase" "installPhase"];

      installPhase = ''
        ${pythonWithYaml}/bin/python ${./crd2jsonschema.py} ${lib.concatStringsSep " " crds} > $out
      '';
    };
in
  import ./jsonschema.nix {
    inherit name pkgs lib;
    spec = schema;
  }
