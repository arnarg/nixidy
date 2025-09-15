{
  pkgs,
  lib,
}:
let
  includedLib = [
    {
      name = "helm";
      description = "helm functions";
    }
    {
      name = "kustomize";
      description = "kustomize functions";
    }
    {
      name = "kube";
      description = "kubernetes resource functions";
    }
  ];

  libMd = pkgs.stdenv.mkDerivation {
    name = "nixidy-lib-docs";

    src = ../lib;

    buildInputs = with pkgs; [
      nixdoc
      gnused
    ];

    installPhase = ''
      mkdir -p $out
      cat <<EOF > $out/lib.md
      # Libary Functions

      The argument ''\\`lib''\\` is passed to each module in nixidy. This is the [standard nixpkgs library](https://nixos.org/manual/nixpkgs/stable/#id-1.4) extended with the following functions.

      EOF

      ${lib.concatMapStrings (
        {
          name,
          description,
        }:
        ''
          nixdoc -c ${name} -f "${name}.nix" -d "${description}" | \
            sed -E ''\'s|^# `.+` usage example|**Example:**|g''\' | \
            sed -E ''\'s|^## `([^`]+)`.*$|## \1|g''\' | \
            sed -E ''\'s|^# .*$||g''\' | \
            sed -E ''\'s|^:::.*$||g''\' >> $out/lib.md
        ''
      ) includedLib}
    '';
  };
in
libMd
