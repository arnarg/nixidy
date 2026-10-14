{
  lib,
  config,
  ...
}:
let
  # Templates are implemented by creating an application import
  # for each template.
  # This function turns a template name, options and `output` function
  # into a module that can be imported with `applicationImports`.
  mkImportable =
    name: opts: func:
    { config, ... }@args:
    let
      mod = {
        options = opts;
      };
    in
    {
      options = with lib; {
        templates."${name}" = mkOption {
          type = with lib.types; attrsOf (submodule mod);
          default = { };
        };
      };

      config = {
        resources =
          with lib;
          mkMerge (
            mapAttrsToList (
              n: v:
              func (
                args
                // {
                  name = n;
                  config = v;
                }
              )
            ) config.templates."${name}"
          );
      };
    };

  tmplMod =
    { config, ... }:
    {
      options = with lib; {
        options =
          let
            optType = mkOptionType {
              name = "option";
              description = "option";
              descriptionClass = "noun";
              check = isOption;
              merge = mergeEqualOption;
            };
            # `recOptType` references itself, which is fine for evaluation,
            # but forcing the type's `description` (as option documentation
            # generation does) recurses forever. Give it an explicit
            # description to break that cycle; the sub-options of options
            # defined by users aren't documented.
            recOptType =
              let
                base = with lib.types; either optType (attrsOf recOptType);
              in
              base
              // {
                description = "option";
                descriptionClass = "noun";
              };
          in
          mkOption {
            type = with lib.types; attrsOf recOptType;
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
in
{
  options.templates = lib.mkOption {
    type = with lib.types; attrsOf (submodule tmplMod);
    default = { };
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

  config = {
    nixidy.applicationImports = lib.mapAttrsToList (
      name: val: mkImportable name val.options val.output
    ) config.templates;
  };
}
