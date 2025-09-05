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

  # We need to re-define this here because `templates.options`
  # defines a recursive type and the options doc generator
  # ends up in an infinite recursion.
  # TODO: Fix "declared by" for templates options
  templatesCompat = let
    mod = {
      options = with lib; {
        options = let
          optType = mkOptionType {
            name = "option";
            description = "option";
            descriptionClass = "noun";
            check = isOption;
            merge = mergeEqualOption;
          };
        in
          mkOption {
            type = with lib.types; attrsOf optType;
            description = ''
              A set of module options that define the configurable parameters for your template.
            '';
          };
        output = mkOption {
          type = with lib.types; functionTo (attrsOf anything);
          description = ''
            A Nix function that takes the template instance's `name` and its `config` (derived from the `options` you defined) and returns a set of nixidy resources (e.g., deployments, services, ingresses).
          '';
        };
      };
    };
  in {
    options.templates = lib.mkOption {
      type = with lib.types; attrsOf (submodule mod);
      default = {};
      description = ''
        Defines reusable templates that can be used in applications. See [documentation](/user_guide/templates/).
      '';
      example = lib.literalMD ''
        {
          webApplication = {
            options = with lib; {
              image = mkOption {
                type = lib.types.str;
                description = "The image to use in the web application deployment";
              };
              replicas = mkOption {
                type = lib.types.int;
                default = 3;
                description = "The number of replicas for the web application deployment.";
              };
              port = mkOption {
                type = lib.types.port;
                default = 8080;
                description = "The web application's port.";
              };
              ingressHost = mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = "The application's ingress host. Set to null to disable ingress.";
              };
            };

            output = {
              name,
              config,
              ...
            }: let
              cfg = config;
              appLabels = {
                "app.kubernetes.io/name" = name;
                "app.kubernetes.io/instance" = name;
              };
            in {
              deployments."''${name}".spec = {
                replicas = cfg.replicas;
                selector.matchLabels = appLabels;
                template = {
                  metadata.labels = appLabels;
                  spec.containers."''${name}" = {
                    image = cfg.image;
                    ports."http".containerPort = cfg.port;
                  };
                };
              };

              services."''${name}".spec = {
                selector = appLabels;
                ports.http = {
                  port = cfg.port;
                  targetPort = cfg.port;
                };
              };

              ingresses = lib.mkIf (cfg.ingressHost != null) {
                "''${name}".spec = {
                  rules = [
                    {
                      host = cfg.ingressHost;
                      http.paths = [
                        {
                          path = "/";
                          pathType = "Prefix";
                          backend.service = {
                            inherit name;
                            port.number = cfg.port;
                          };
                        }
                      ];
                    }
                  ];
                };
              };
            };
          };
        };
      '';
    };
  };

  options =
    (lib.evalModules {
      modules =
        import ../modules/modules.nix
        ++ [
          {
            nixidy.baseImports = false;
            nixidy.applicationImports = [resourcesCompat];
          }
          templatesCompat
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
        + (
          if (length opt.declarations > 0)
          then ''
            ***Declared by:***

            ${
              concatStringsSep "\n" (map (
                  decl: ''
                    - [&lt;${decl.name}&gt;](${decl.url})
                  ''
                )
                opt.declarations)
            }
          ''
          else ""
        ))
      optionsDoc.optionsNix));
in
  optsMd
