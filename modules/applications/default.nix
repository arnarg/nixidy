{
  name,
  nixidyDefaults,
  lib,
  config,
  ...
}: let
  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  gvkKeyFn = type: "${type.group}/${type.version}/${type.kind}";

  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  coerceListOfSubmodulesToAttrs = with lib;
    submodule: keyFn: let
      mergeValuesByFn = keyFn: values:
        listToAttrs (map
          (
            value:
              nameValuePair (toString (keyFn value)) value
          )
          values);

      # Either value of type `finalType` or `coercedType`, the latter is
      # converted to `finalType` using `coerceFunc`.
      coercedTo = coercedType: coerceFunc: finalType:
        mkOptionType rec {
          name = "coercedTo";
          description = "${finalType.description} or ${coercedType.description}";
          check = x: finalType.check x || coercedType.check x;
          merge = loc: defs: let
            coerceVal = val:
              if finalType.check val
              then val
              else let coerced = coerceFunc val; in assert finalType.check coerced; coerced;
          in
            finalType.merge loc (map (def: def // {value = coerceVal def.value;}) defs);
          inherit (finalType) getSubOptions;
          inherit (finalType) getSubModules;
          substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
          typeMerge = _t1: _t2: null;
          functor = (defaultFunctor name) // {wrapped = finalType;};
        };
    in
      coercedTo
      (types.listOf (types.submodule submodule))
      (mergeValuesByFn keyFn)
      (types.attrsOf (types.submodule submodule));

  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  moduleToAttrs = with lib;
    value:
      if isAttrs value
      then mapAttrs (_n: moduleToAttrs) (filterAttrs (n: v: v != null && !(hasPrefix "_" n)) value)
      else if isList value
      then map moduleToAttrs value
      else value;
in {
  imports = [
    ./helm.nix
    ./kustomize.nix
    ./yamls.nix
    ./namespaced.nix
  ];

  options = with lib; {
    name = mkOption {
      type = types.str;
      default = name;
      description = "Name of the application.";
    };
    namespace = mkOption {
      type = types.str;
      default = name;
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
    syncPolicy = {
      automated = {
        prune = mkOption {
          type = types.bool;
          default = nixidyDefaults.syncPolicy.automated.prune;
          defaultText = literalExpression "config.nixidy.defaults.syncPolicy.automated.prune";
          description = ''
            Specifies if resources should be pruned during auto-syncing.
          '';
        };
        selfHeal = mkOption {
          type = types.bool;
          default = nixidyDefaults.syncPolicy.automated.selfHeal;
          defaultText = literalExpression "config.nixidy.defaults.syncPolicy.automated.selfHeal";
          description = ''
            Specifies if partial app sync should be executed when resources are changed only in
            target Kubernetes cluster and no git change detected.
          '';
        };
      };
    };
    output = {
      path = mkOption {
        type = types.str;
        default = name;
        description = ''
          Name of the folder that contains all rendered resources for the application. Relative to the root of the repository.
        '';
      };
    };
    objects = mkOption {
      type = with types; listOf attrs;
      apply = unique;
      default = [];
      internal = true;
    };

    # Options for resource definitions
    definitions = mkOption {
      description = "Attribute set of kubernetes definitions";
      internal = true;
    };
    defaults = mkOption {
      description = "Kubernetes defaults to apply to resources";
      type = types.listOf (types.submodule (_: {
        options = {
          group = mkOption {
            description = "Group to apply default to (all by default)";
            type = types.nullOr types.str;
            default = null;
            internal = true;
          };

          version = mkOption {
            description = "Version to apply default to (all by default)";
            type = types.nullOr types.str;
            default = null;
            internal = true;
          };

          kind = mkOption {
            description = "Kind to apply default to (all by default)";
            type = types.nullOr types.str;
            default = null;
            internal = true;
          };

          resource = mkOption {
            description = "Resource to apply default to (all by default)";
            type = types.nullOr types.str;
            default = null;
            internal = true;
          };

          propagate = mkOption {
            description = "Whether to propagate defaults";
            type = types.bool;
            default = false;
            internal = true;
          };

          default = mkOption {
            description = "Default to apply";
            type = types.unspecified;
            default = {};
            internal = true;
          };
        };
      }));
      default = [];
      apply = unique;
      internal = true;
    };
    types = mkOption {
      description = "List of registered kubernetes types";
      type =
        coerceListOfSubmodulesToAttrs
        {
          options = {
            group = mkOption {
              description = "Resource type group";
              type = types.str;
              internal = true;
            };
            version = mkOption {
              description = "Resoruce type version";
              type = types.str;
              internal = true;
            };
            kind = mkOption {
              description = "Resource type kind";
              type = types.str;
              internal = true;
            };
            name = mkOption {
              description = "Resource type name";
              type = types.nullOr types.str;
              internal = true;
            };
            attrName = mkOption {
              description = "Name of the nixified attribute";
              type = types.str;
              internal = true;
            };
          };
        }
        gvkKeyFn;
      default = {};
      internal = true;
    };
  };

  config = {
    resources = lib.mkIf config.createNamespace {
      namespaces.${config.namespace} = {};
    };

    objects = with lib;
      flatten (mapAttrsToList (
          _: type:
            mapAttrsToList (_: res: moduleToAttrs res) config.resources.${type.group}.${type.version}.${type.kind}
        )
        config.types);
  };
}
