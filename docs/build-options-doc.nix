{
  pkgs,
  lib,
}:
let
  nixidyPath = toString ./..;

  # Borrowed from home-manager :)
  gitHubDeclaration = user: repo: subpath: {
    url = "https://github.com/${user}/${repo}/blob/main/${subpath}";
    name = "${repo}/${subpath}";
  };

  resourcesCompat =
    { lib, ... }:
    {
      options.resources =
        with lib;
        mkOption {
          type = types.attrs;
          default = { };
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

            The resource options are generated from the Kubernetes API and are too many to list here. They follow `resources.<group>.<version>.<kind>.<name>` (e.g. `resources.apps.v1.Deployment.nginx`) and their fields match the [Kubernetes API reference](https://kubernetes.io/docs/reference/kubernetes-api/).

            To browse them, including the ones generated from CRDs, use [`nixidy resources`](cli_reference.md#nixidy-resources), e.g. `nixidy resources .#prod deployments.spec.template.spec`.
          '';
        };
    };

  options =
    (lib.evalModules {
      modules = import ../modules/modules.nix ++ [
        {
          nixidy.baseImports = false;
          nixidy.applicationImports = [ resourcesCompat ];
        }
      ];
      specialArgs = {
        inherit pkgs lib;
      };
    }).options;

  optionsDoc = pkgs.buildPackages.nixosOptionsDoc {
    options = removeAttrs options [ "_module" ];
    transformOptions =
      opt:
      opt
      // {
        declarations = map (
          decl:
          if lib.hasPrefix nixidyPath (toString decl) then
            gitHubDeclaration "arnarg" "nixidy" (
              lib.removePrefix "/" (lib.removePrefix nixidyPath (toString decl))
            )
          else if decl == "lib/modules.nix" then
            gitHubDeclaration "NixOS" "nixpkgs" decl
          else
            decl
        ) opt.declarations;
      };
  };

  optsMd =
    with lib;
    concatStringsSep "\n" (
      [
        ''
          ---
          title: Configuration Options
          nav:
            section: reference
            order: 30
          ---

          The resource options under `applications.<name>.resources` are too many to list here. To browse all available resource types and their options, including the ones generated from CRDs, use the [`nixidy resources`](cli_reference.md#nixidy-resources) command:

          ```sh
          # List all resource types.
          nixidy resources .#prod

          # Show the options at a path.
          nixidy resources .#prod deployments.spec.template.spec
          ```
        ''
      ]
      ++ (mapAttrsToList (
        n: opt:
        ''
          ## ${replaceStrings [ "\<" ">" ] [ "&lt;" "&gt;" ] n}

          ${if opt.description != null then opt.description else ""}

          ***Type:***
          ${opt.type}

        ''
        + (lib.optionalString (hasAttrByPath [ "default" "text" ] opt) ''
          ***Default:***
          `#!nix ${opt.default.text}`

        '')
        + (lib.optionalString (hasAttrByPath [ "example" "text" ] opt) (
          ''
            ***Example:***
          ''
          + (
            if (hasPrefix "attribute set" opt.type) || (hasPrefix "list of" opt.type) then
              ''

                ```nix
                ${opt.example.text}
                ```

              ''
            else
              ''
                `#!nix ${opt.example.text}`

              ''
          )
        ))
        + (
          if (length opt.declarations > 0) then
            ''
              ***Declared by:***

              ${concatStringsSep "\n" (
                map (decl: ''
                  - [&lt;${decl.name}&gt;](${decl.url})
                '') opt.declarations
              )}
            ''
          else
            ""
        )
      ) optionsDoc.optionsNix)
    );
in
optsMd
