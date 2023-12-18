{
  pkgs,
  lib ? pkgs.lib,
}: let
  optionsMd = import ./build-options-doc.nix {inherit pkgs lib;};

  libraryMd = import ./build-library-doc.nix {inherit pkgs lib;};

  docsHtml = pkgs.stdenv.mkDerivation {
    inherit optionsMd;

    passAsFile = ["optionsMd"];

    name = "nixidy-html-docs";

    src = lib.cleanSource ./..;

    buildInputs = with pkgs.python3.pkgs; [mkdocs-material mkdocs-material-extensions];

    phases = ["unpackPhase" "patchPhase" "buildPhase"];

    patchPhase = ''
      cat $optionsMdPath > docs/options.md
      cp ${libraryMd}/lib.md docs/library.md
      cp ${../README.md} docs/index.md

      cat <<EOF > mkdocs.yml
        site_name: nixidy
        site_url: https://arnarg.github.io/nixidy/
        site_dir: $out

        repo_url: https://github.com/arnarg/nixidy/

        exclude_docs: |
          *.nix

        theme:
          name: material

          features:
          - content.code.annotate

          palette:
          - media: "(prefers-color-scheme: light)"
            scheme: default
            toggle:
              icon: material/brightness-7
              name: Switch to dark mode
          - media: "(prefers-color-scheme: dark)"
            scheme: slate
            toggle:
              icon: material/brightness-4
              name: Switch to light mode

        markdown_extensions:
        - def_list
        - toc:
            permalink: "#"
            toc_depth: 3
        - admonition
        - pymdownx.highlight
        - pymdownx.inlinehilite
        - pymdownx.superfences
        - pymdownx.tabbed:
            alternate_style: true

        nav:
        - Home: index.md
        - 'User Guide':
          - 'Getting Started': user_guide/getting_started.md
          - 'More Environments': user_guide/more_environments.md
        - Reference:
          - 'Library Functions': library.md
          - 'Configuration Options': options.md
      EOF
    '';

    buildPhase = ''
      mkdir -p $out
      python -m mkdocs build
    '';
  };
in {
  html = docsHtml;
}
