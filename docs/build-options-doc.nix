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

  options =
    (lib.evalModules {
      modules = import ../modules/modules.nix;
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
