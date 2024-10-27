{
  pkgs,
  lib,
  kubenix,
  mkSearch,
}: let
  nixidyPath = toString ./..;
  kubenixPath = toString kubenix;

  # Borrowed from home-manager :)
  gitHubDeclaration = user: repo: subpath: {
    url = "https://github.com/${user}/${repo}/blob/main/${subpath}";
    name = "${repo}/${subpath}";
  };

  options =
    (lib.evalModules {
      modules =
        import ../modules/modules.nix
        ++ [
          {
            nixidy.resourceImports = [
              (kubenix + "/modules/generated/v1.30.nix")
              ../modules/generated/argocd.nix
            ];
          }
        ];
      specialArgs = {
        inherit pkgs lib;
      };
    })
    .options;

  optionsJSON =
    (pkgs.buildPackages.nixosOptionsDoc {
      options = removeAttrs options ["_module"];
      transformOptions = opt:
        opt
        // {
          declarations =
            map (
              decl:
                if lib.hasPrefix nixidyPath (toString decl)
                then gitHubDeclaration "arnarg" "nixidy" (lib.removePrefix "/" (lib.removePrefix nixidyPath (toString decl)))
                else if lib.hasPrefix kubenixPath (toString decl)
                then gitHubDeclaration "hall" "kubenix" (lib.removePrefix "/" (lib.removePrefix kubenixPath (toString decl)))
                else if decl == "lib/modules.nix"
                then gitHubDeclaration "NixOS" "nixpkgs" decl
                else decl
            )
            opt.declarations;
        }
        // (lib.optionalAttrs (opt.description == null) {
          description = "";
        });
    })
    .optionsJSON;
in
  baseHref:
    mkSearch {
      inherit baseHref;
      optionsJSON = optionsJSON + "/share/doc/nixos/options.json";
      urlPrefix = "https://github.com/arnarg/nixidy/tree/main";
      title = "nixidy options search";
    }
