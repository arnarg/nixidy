{
  pkgs,
  lib,
}: let
  nixidyPath = toString ./..;

  # Borrowed from home-manager :)
  gitHubDeclaration = user: repo: subpath: {
    url = "https://github.com/${user}/${repo}/blob/main/${subpath}";
    name = "${repo}/${subpath}";
  };

  resourcesCompat = {lib, ...}: {
    options.resources = with lib;
      mkOption {
        type = types.attrs;
        default = {};
        example = {
          deployments.nginx.spec = {
            replicas = 3;
            selector.matchLabels.app = "nginx";
            template = {
              metadata.labels.app = "nginx";
              spec = {
                securityContext.fsGroup = 1000;
                containers.nginx = {
                  image = "nginx:1.25.1";
                  imagePullPolicy = "IfNotPresent";
                };
              };
            };
          };

          services.nginx.spec = {
            selector.app = "nginx";
            ports.http.port = 80;
          };
        };
        description = ''
          Kubernetes resources for the application.

          The entire list of available resource options is too large for the current documentation setup but can be searched in the [nixidy options search](search) powered by [NüschtOS](https://github.com/NuschtOS/search).
        '';
      };
  };

  options =
    (lib.evalModules {
      modules =
        import ../modules/modules.nix
        ++ [
          {
            nixidy.applicationImports = [resourcesCompat];
          }
        ];
      specialArgs = {
        inherit pkgs lib;
      };
    })
    .options;

  optionsDoc = pkgs.buildPackages.nixosOptionsDoc {
    options = removeAttrs options ["_module"];
    transformOptions = opt:
      opt
      // {
        declarations =
          map (
            decl:
              if lib.hasPrefix nixidyPath (toString decl)
              then gitHubDeclaration "arnarg" "nixidy" (lib.removePrefix "/" (lib.removePrefix nixidyPath (toString decl)))
              else if decl == "lib/modules.nix"
              then gitHubDeclaration "NixOS" "nixpkgs" decl
              else decl
          )
          opt.declarations;
      };
  };

  optsMd = with lib;
    concatStringsSep "\n" ([
        ''
          # Configuration Options

          To see all available resources options, use the [nixidy options search](search) powered by [NüschtOS](https://github.com/NuschtOS/search).
        ''
      ]
      ++ (mapAttrsToList (n: opt:
        ''
          ## ${replaceStrings ["\<" ">"] ["&lt;" "&gt;"] n}

          ${opt.description}

          ***Type:***
          ${opt.type}

        ''
        + (lib.optionalString (hasAttrByPath ["default" "text"] opt) ''
          ***Default:***
          `#!nix ${opt.default.text}`

        '')
        + (lib.optionalString (hasAttrByPath ["example" "text"] opt) (''
            ***Example:***
          ''
          + (
            if
              (hasPrefix "attribute set" opt.type)
              || (hasPrefix "list of" opt.type)
            then ''

              ```nix
              ${opt.example.text}
              ```

            ''
            else ''
              `#!nix ${opt.example.text}`

            ''
          )))
        + ''
          ***Declared by:***

          ${
            concatStringsSep "\n" (map (
                decl: ''
                  - [&lt;${decl.name}&gt;](${decl.url})
                ''
              )
              opt.declarations)
          }
        '')
      optionsDoc.optionsNix));
in
  optsMd
