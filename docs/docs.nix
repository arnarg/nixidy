{
  pkgs,
  lib ? pkgs.lib,
  nixtml,
}:
let
  optionsMd = import ./build-options-doc.nix { inherit pkgs lib; };

  libraryMd = import ./build-library-doc.nix { inherit pkgs lib; };

  python3Packages = pkgs.python3Packages;

  # Make a python package of the CLI for mkdocs-click to find it.
  cli-package =
    let
      src = ../cli;
      pyproject = lib.importTOML "${src}/pyproject.toml";
    in
    python3Packages.buildPythonPackage {
      inherit src;

      pname = "nixidy";
      version = pyproject.project.version;
      pyproject = true;

      build-system = with python3Packages; [
        setuptools
      ];

      dependencies = with python3Packages; [
        click
      ];

      doCheck = false;
    };

  # Package mkdocs-click to automatically generate CLI reference
  # from click definitions. Despite its name it's a regular
  # Python-Markdown extension and works without mkdocs.
  mkdocs-click =
    let
      pname = "mkdocs_click";
      version = "0.9.0";

      src = pkgs.fetchPypi {
        inherit pname version;
        hash = "sha256-YFCRdijUdAUXVBQitgdATQRBF7wxt3DE+enhk5pQyQg=";
      };
    in
    python3Packages.buildPythonPackage {
      inherit pname version src;
      pyproject = true;

      build-system = with python3Packages; [
        hatchling
      ];

      dependencies = with python3Packages; [
        click
        markdown
      ];

      doCheck = false;
    };

  website = nixtml.lib.evalModules {
    inherit pkgs;
    modules = [
      nixtml.themes.docs
      {
        website = {
          name = "nixidy-docs";
          baseURL = "https://nixidy.dev";

          metadata = {
            lang = "en";
            title = "nixidy";
            description = "Kubernetes GitOps with nix and Argo CD.";
          };

          content = {
            dir = ./content;

            pages = {
              options.text = optionsMd;
              library.source = "${libraryMd}/lib.md";
            };

            processors.md = {
              settings = {
                # Resolve links like `./helm_charts.md` against the markdown
                # file, as on GitHub.
                relativeLinks.enable = true;
                toc = {
                  permalink = "#";
                  permalinkClass = "headerlink mx-2";
                };
                extensions.mkdocs_click = { };
              };
              extraPythonPackages = [
                mkdocs-click
                cli-package
              ];
            };
          };

          static.dir = ./static;

          files."llms.txt".source = ./llms.txt;
        };

        themes.docs = {
          logo = {
            source = ../logo.svg;
            # Only the helmet, displayed in front of the site title in the
            # bar and used as the favicon.
            compact.source = ./logo-compact.svg;
          };

          # The badges from the README.
          hero.content = ''
            <p>
              <a href="https://github.com/arnarg/nixidy/blob/main/LICENSE"><img src="https://img.shields.io/github/license/arnarg/nixidy?style=flat" alt="License Badge" /></a>
              <a href="https://github.com/arnarg/nixidy/releases"><img src="https://img.shields.io/github/v/tag/arnarg/nixidy?style=flat&label=release&color=0a7cbd" alt="Latest Release Badge" /></a>
              <img src="https://img.shields.io/github/check-runs/arnarg/nixidy/main?style=flat" alt="Checks Passing Badge" />
            </p>
          '';

          # A larger logo than the theme's default.
          extraScss = ''
            @use "bulma/sass/utilities/mixins";

            .docs-hero-logo {
              width: min(100%, 26rem);
            }

            @include mixins.mobile {
              .docs-hero-logo {
                width: min(100%, 18rem);
              }
            }
          '';

          # Colors from the logo.
          colors = {
            primary = "#1d5184";
            link = "#2173bd";
            warning = "#f0b022";
          };

          repository.url = "https://github.com/arnarg/nixidy";
          editLink.baseURL = "https://github.com/arnarg/nixidy/edit/main/docs/content/";

          navigation.sections = [
            {
              id = "user-guide";
              title = "User Guide";
              pager = true;
            }
            {
              id = "developer-guide";
              title = "Developer Guide";
            }
            {
              id = "reference";
              title = "Reference";
            }
          ];
        };
      }
    ];
  };
in
{
  html = website;
}
