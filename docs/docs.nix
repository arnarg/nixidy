{
  pkgs,
  lib ? pkgs.lib,
  mkSearch,
}:
let
  optionsMd = import ./build-options-doc.nix { inherit pkgs lib; };

  buildSearch = import ./build-options-search.nix {
    inherit pkgs lib mkSearch;
  };

  libraryMd = import ./build-library-doc.nix { inherit pkgs lib; };

  docsHtml = pkgs.stdenv.mkDerivation {
    inherit optionsMd;

    passAsFile = [ "optionsMd" ];

    name = "nixidy-html-docs";

    src = lib.cleanSource ./..;

    buildInputs = with pkgs.python3.pkgs; [
      mkdocs-material
      mkdocs-material-extensions
    ];

    phases = [
      "unpackPhase"
      "patchPhase"
      "buildPhase"
    ];

    patchPhase = ''
      cat $optionsMdPath > docs/options.md
      cp ${libraryMd}/lib.md docs/library.md
      cp ${../logo.svg} docs/logo.svg

      cat <<EOF > docs/index.md
      ---
      template: home.html
      ---
      EOF
      cat ${../README.md} >> docs/index.md

      cat <<EOF > mkdocs.yml
        site_name: nixidy
        site_url: https://nixidy.dev/
        site_dir: $out

        repo_url: https://github.com/arnarg/nixidy/

        exclude_docs: |
          *.nix
          /npins/
          /overrides/

        extra_css:
        - stylesheets/extra.css

        theme:
          name: material
          custom_dir: docs/overrides

          logo: images/icon.svg
          favicon: images/icon.svg

          palette:
          - media: "(prefers-color-scheme: light)"
            scheme: default
            primary: custom
            toggle:
              icon: material/brightness-7
              name: Switch to dark mode
          - media: "(prefers-color-scheme: dark)"
            scheme: slate
            primary: custom
            toggle:
              icon: material/brightness-4
              name: Switch to light mode

          features:
          - navigation.footer
          - content.tabs.link

        markdown_extensions:
        - def_list
        - toc:
            permalink: "#"
            toc_depth: 3
        - admonition
        - pymdownx.highlight
        - pymdownx.inlinehilite
        - pymdownx.superfences:
            custom_fences:
            - name: mermaid
              class: mermaid
              format: !!python/name:pymdownx.superfences.fence_code_format
        - pymdownx.details
        - pymdownx.tabbed:
            alternate_style: true

        nav:
        - Home: index.md
        - 'User Guide':
          - 'Getting Started': user_guide/getting_started.md
          - 'Using Helm Charts': user_guide/helm_charts.md
          - 'Typed Resource Options': user_guide/typed_resources.md
          - 'Templates': user_guide/templates.md
          - 'Git Strategies': user_guide/git_strategies.md
          - 'GitHub Actions': user_guide/github_actions.md
          - 'Transformers': user_guide/transformers.md
          - 'Using nixhelm': user_guide/using_nixhelm.md
          - 'Directly Apply Manifests': user_guide/direct_apply.md
        - 'Developer Guide':
          - 'Architecture Guide': developer_guide/architecture.md
        - Reference:
          - 'Library Functions': library.md
          - 'Configuration Options': options.md
      EOF
    '';

    buildPhase = ''
      mkdir -p $out
      python -m mkdocs build

      cp -r ${buildSearch "/options/search/"} $out/options/search
    '';
  };
in
{
  html = docsHtml;
  search = buildSearch "/";
}
