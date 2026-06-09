{
  name,
  lib,
  config,
  ...
}:
{
  imports = [
    ./helm.nix
    ./kustomize.nix
    ./yamls.nix
    ./argocd.nix
    ./objects.nix
  ];

  options = with lib; {
    name = mkOption {
      type = types.str;
      default = name;
      description = "Name of the application.";
    };
    namespace = mkOption {
      type = types.str;
      default = config.name;
      description = "Namespace to deploy application into (defaults to name).";
    };
    createNamespace = mkOption {
      type = types.bool;
      default = false;
      description = "Whether or not a namespace resource should be automatically created.";
    };
    project = mkOption {
      type = types.str;
      default = "default";
      description = "ArgoCD project to make application a part of.";
    };
    annotations = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Annotations to add to the rendered ArgoCD application.";
    };
    labels = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Labels to add to the rendered ArgoCD application.";
    };
    output = {
      path = mkOption {
        type = types.str;
        default = config.name;
        description = ''
          Name of the folder that contains all rendered resources for the application. Relative to the root of the repository.
        '';
      };
    };
    objectTransforms = mkOption {
      type = types.listOf (import ../nixidy/transforms.nix { inherit lib; }).ruleType;
      default = [ ];
      description = "Resource transform rules applied to this application's objects.";
    };
    assertions = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            assertion = mkOption {
              type = types.bool;
              description = "Whether the assertion holds";
            };
            message = mkOption {
              type = types.str;
              description = "Message to display if assertion fails";
            };
          };
        }
      );
      default = [ ];
      apply = map (a: {
        inherit (a) assertion message;
        context = config.name;
      });
      description = ''
        List of assertions that must hold during build time. If any assertion is false,
        the build will fail with the corresponding message.
      '';
    };
    warnings = mkOption {
      type = types.listOf (
        types.coercedTo (types.str)
          (x: {
            when = true;
            message = x;
          })
          (
            types.submodule {
              options = {
                when = mkOption {
                  type = types.bool;
                  default = false;
                };
                message = mkOption {
                  type = types.str;
                };
              };
            }
          )
      );
      default = [ ];
      apply = map (warning: {
        inherit (warning) when message;
        context = config.name;
      });
      description = ''
        List of warnings that will be printed during build time when `when` is `true`, but will not fail the build.
      '';
    };
  };

  config = {
    assertions = lib.imap0 (i: r: {
      assertion = (r.map != null) != (r.render != null);
      message = "application `${name}` objectTransforms rule ${toString i}: set exactly one of `map` or `render`.";
    }) config.objectTransforms;

    # If createNamespace is set to `true` we should
    # create one.
    resources = lib.mkIf config.createNamespace {
      namespaces.${config.namespace} = {
        metadata.annotations."argocd.argoproj.io/sync-options" = "Prune=false";
      };
    };
  };
}
