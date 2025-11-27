{
  name,
  nixidyDefaults,
  lib,
  config,
  ...
}:
let
  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  gvkKeyFn = type: "${type.group}/${type.version}/${type.kind}";

  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  coerceListOfSubmodulesToAttrs =
    with lib;
    submodule: keyFn:
    let
      mergeValuesByFn =
        keyFn: values: listToAttrs (map (value: nameValuePair (toString (keyFn value)) value) values);

      # Either value of type `finalType` or `coercedType`, the latter is
      # converted to `finalType` using `coerceFunc`.
      coercedTo =
        coercedType: coerceFunc: finalType:
        mkOptionType rec {
          name = "coercedTo";
          description = "${finalType.description} or ${coercedType.description}";
          check = x: finalType.check x || coercedType.check x;
          merge =
            loc: defs:
            let
              coerceVal =
                val:
                if finalType.check val then
                  val
                else
                  let
                    coerced = coerceFunc val;
                  in
                  assert finalType.check coerced;
                  coerced;
            in
            finalType.merge loc (map (def: def // { value = coerceVal def.value; }) defs);
          inherit (finalType) getSubOptions;
          inherit (finalType) getSubModules;
          substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
          typeMerge = _t1: _t2: null;
          functor = (defaultFunctor name) // {
            wrapped = finalType;
          };
        };
    in
    coercedTo (types.listOf (types.submodule submodule)) (mergeValuesByFn keyFn) (
      types.attrsOf (types.submodule submodule)
    );

  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  moduleToAttrs =
    with lib;
    value:
    if isAttrs value then
      mapAttrs (_n: moduleToAttrs) (filterAttrs (n: v: v != null && !(hasPrefix "_priority" n)) value)
    else if isList value then
      map moduleToAttrs value
    else
      value;

  applyCmpOption = apply: val: if val == null then null else apply val;

  convertCmpOptionsAnnotation =
    opts:
    let
      filtered = lib.filter (val: val != null) (lib.mapAttrsToList (_: val: val) opts);
    in
    lib.mkIf (lib.length filtered > 0) {
      "argocd.argoproj.io/compare-options" = lib.mkDefault (lib.concatStringsSep "," filtered);
    };

  convertSyncOptionsList =
    opts:
    let
      filtered = lib.filter (val: val != null) (lib.mapAttrsToList (_: val: val) opts);
    in
    filtered;

  syncPolicy = import ./syncPolicy.nix { inherit lib nixidyDefaults; };
in
{
  imports = [
    ./helm.nix
    ./kustomize.nix
    ./yamls.nix

    (lib.mkRenamedOptionModule
      [ "syncPolicy" "autoSync" "enabled" ]
      [ "syncPolicy" "autoSync" "enable" ]
    )
  ];

  options = with lib; {
    inherit syncPolicy;

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
    compareOptions = {
      serverSideDiff = mkOption {
        type = types.nullOr types.bool;
        default = null;
        apply = applyCmpOption (val: "ServerSideDiff=${if val then "true" else "false"}");
        description = "Sets ServerSideDiff compare option for the application. Leave as `null` for the default behavior.";
      };
      includeMutationWebhook = mkOption {
        type = types.nullOr types.bool;
        default = null;
        apply = applyCmpOption (val: if val then "IncludeMutationWebhook=true" else null);
        description = "Sets IncludeMutationWebhook compare option for the application. Only setting it as `true` has any effect.";
      };
      ignoreExtraneous = mkOption {
        type = types.nullOr types.bool;
        default = null;
        apply = applyCmpOption (val: if val then "IgnoreExtraneous" else null);
        description = "Sets IgnoreExtraneous compare option for the application. Only setting it as `true` has any effect.";
      };
    };
    destination = {
      name = mkOption {
        type = types.nullOr types.str;
        default = nixidyDefaults.destination.name;
        defaultText = literalExpression "config.nixidy.defaults.destination.name";
        description = ''
          The name of the cluster that ArgoCD should deploy all applications to.
        '';
      };
      server = mkOption {
        type = types.nullOr types.str;
        default = nixidyDefaults.destination.server;
        defaultText = literalExpression "config.nixidy.defaults.destination.server";
        description = ''
          The Kubernetes server that ArgoCD should deploy the application to.
        '';
      };
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
    ignoreDifferences =
      let
        submoduleType = types.submodule (
          { name, ... }:
          {
            options = {
              group = mkOption {
                description = "";
                default = null;
                type = types.nullOr types.str;
              };
              jqPathExpressions = mkOption {
                description = "";
                default = null;
                type = types.nullOr (types.listOf types.str);
              };
              jsonPointers = mkOption {
                description = "";
                default = null;
                type = types.nullOr (types.listOf types.str);
              };
              kind = mkOption {
                description = "";
                default = name;
                type = types.str;
              };
              managedFieldsManagers = mkOption {
                description = "ManagedFieldsManagers is a list of trusted managers. Fields mutated by those managers will take precedence over the\ndesired state defined in the SCM and won't be displayed in diffs";
                default = null;
                type = types.nullOr (types.listOf types.str);
              };
              name = mkOption {
                description = "";
                default = null;
                type = types.nullOr types.str;
              };
              namespace = mkOption {
                description = "";
                default = null;
                type = types.nullOr types.str;
              };
            };
          }
        );
      in
      mkOption {
        type = with types; nullOr (attrsOf submoduleType);
        description = ''
          IgnoreDifferences is a list of resources and their fields which should be ignored during comparison.

          More info [here](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/).
        '';
        default = null;
      };
    objects = mkOption {
      type = with types; listOf attrs;
      apply = unique;
      default = [ ];
      internal = true;
    };

    # Options for resource definitions
    definitions = mkOption {
      description = "Attribute set of kubernetes definitions";
      internal = true;
    };
    defaults = mkOption {
      description = "Kubernetes defaults to apply to resources";
      type = types.listOf (
        types.submodule (_: {
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
              default = { };
              internal = true;
            };
          };
        })
      );
      default = [ ];
      apply = unique;
      internal = true;
    };
    types = mkOption {
      description = "List of registered kubernetes types";
      type = coerceListOfSubmodulesToAttrs {
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
      } gvkKeyFn;
      default = { };
      internal = true;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.syncPolicy.managedNamespaceMetadata != null) {
      syncPolicy.syncOptions.createNamespace = lib.mkDefault true;
    })

    {
      # If createNamespace is set to `true` we should
      # create one.
      resources = lib.mkIf config.createNamespace {
        namespaces.${config.namespace} = {
          metadata.annotations."argocd.argoproj.io/sync-options" = "Prune=false";
        };
      };

      # Turn all typed resources into standard kubernetes
      # objects that will be written to YAML files.
      objects =
        with lib;
        flatten (
          mapAttrsToList (
            _: type:
            mapAttrsToList (_: moduleToAttrs) config.resources.${type.group}.${type.version}.${type.kind}
          ) config.types
        );

      annotations = convertCmpOptionsAnnotation config.compareOptions;

      syncPolicy.finalSyncOpts = convertSyncOptionsList config.syncPolicy.syncOptions;
    }
  ];
}
