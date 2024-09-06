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

  applyCmpOption = apply: val:
    if val == null
    then null
    else apply val;

  convertCmpOptionsAnnotation = opts: let
    filtered = lib.filter (val: val != null) (lib.mapAttrsToList (_: val: val) opts);
  in
    lib.mkIf (lib.length filtered > 0) {
      "argocd.argoproj.io/compare-options" = lib.mkDefault (lib.concatStringsSep "," filtered);
    };

  convertSyncOptionsList = opts: let
    filtered = lib.filter (val: val != null) (lib.mapAttrsToList (_: val: val) opts);
  in
    filtered;
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
    promotionGroup = mkOption {
      type = types.str;
      default = "default";
      description = "The promotion group the application should be a part of.";
    };
    project = mkOption {
      type = types.str;
      default = "default";
      description = "ArgoCD project to make application a part of.";
    };
    annotations = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Annotations to add to the rendered ArgoCD application.";
    };
    compareOptions = {
      serverSideDiff = mkOption {
        type = types.nullOr types.bool;
        default = null;
        apply = applyCmpOption (val: "ServerSideDiff=${
          if val
          then "true"
          else "false"
        }");
        description = "Sets ServerSideDiff compare option for the application. Leave as `null` for the default behavior.";
      };
      includeMutationWebhook = mkOption {
        type = types.nullOr types.bool;
        default = null;
        apply = applyCmpOption (val:
          if val
          then "IncludeMutationWebhook=true"
          else null);
        description = "Sets IncludeMutationWebhook compare option for the application. Only setting it as `true` has any effect.";
      };
      ignoreExtraneous = mkOption {
        type = types.nullOr types.bool;
        default = null;
        apply = applyCmpOption (val:
          if val
          then "IgnoreExtraneous"
          else null);
        description = "Sets IgnoreExtraneous compare option for the application. Only setting it as `true` has any effect.";
      };
    };
    syncPolicy = {
      autoSync = {
        enabled = mkOption {
          type = types.bool;
          default = nixidyDefaults.syncPolicy.autoSync.enabled;
          defaultText = literalExpression "config.nixidy.defaults.syncPolicy.autoSync.enabled";
          description = ''
            Specifies if application should automatically sync.
          '';
        };
        prune = mkOption {
          type = types.bool;
          default = nixidyDefaults.syncPolicy.autoSync.prune;
          defaultText = literalExpression "config.nixidy.defaults.syncPolicy.autoSync.prune";
          description = ''
            Specifies if resources should be pruned during auto-syncing.
          '';
        };
        selfHeal = mkOption {
          type = types.bool;
          default = nixidyDefaults.syncPolicy.autoSync.selfHeal;
          defaultText = literalExpression "config.nixidy.defaults.syncPolicy.autoSync.selfHeal";
          description = ''
            Specifies if partial app sync should be executed when resources are changed only in
            target Kubernetes cluster and no git change detected.
          '';
        };
      };
      syncOptions = {
        applyOutOfSyncOnly = mkOption {
          type = types.bool;
          default = false;
          apply = val:
            if val
            then "ApplyOutOfSyncOnly=true"
            else null;
          description = ''
            Currently when syncing using auto sync Argo CD applies every object in the application.
            For applications containing thousands of objects this takes quite a long time and puts undue pressure on the api server.
            Turning on selective sync option which will sync only out-of-sync resources.
          '';
        };
        pruneLast = mkOption {
          type = types.bool;
          default = false;
          apply = val:
            if val
            then "PruneLast=true"
            else null;
          description = ''
            This feature is to allow the ability for resource pruning to happen as a final, implicit wave of a sync operation,
            after the other resources have been deployed and become healthy, and after all other waves completed successfully.
          '';
        };
        replace = mkOption {
          type = types.bool;
          default = false;
          apply = val:
            if val
            then "Replace=true"
            else null;
          description = ''
            By default, Argo CD executes `kubectl apply` operation to apply the configuration stored in Git.
            In some cases `kubectl apply` is not suitable. For example, resource spec might be too big and won't fit into
            `kubectl.kubernetes.io/last-applied-configuration` annotation that is added by kubectl apply.

            If the `replace = true;` sync option is set the Argo CD will use `kubectl replace` or `kubectl create` command
            to apply changes.
          '';
        };
        serverSideApply = mkOption {
          type = types.bool;
          default = false;
          apply = val:
            if val
            then "ServerSideApply=true"
            else null;
          description = ''
            By default, Argo CD executes `kubectl apply` operation to apply the configuration stored in Git.
            This is a client side operation that relies on `kubectl.kubernetes.io/last-applied-configuration` annotation to
            store the previous resource state.

            If `serverSideApply = true;` sync option is set, Argo CD will use `kubectl apply --server-side` command to apply changes.

            More info [here](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#server-side-apply).
          '';
        };
        failOnSharedResource = mkOption {
          type = types.bool;
          default = false;
          apply = val:
            if val
            then "FailOnSharedResource=true"
            else null;
          description = ''
            By default, Argo CD will apply all manifests found in the git path configured in the Application regardless if the
            resources defined in the yamls are already applied by another Application. If the `failOnSharedResource` sync option
            is set, Argo CD will fail the sync whenever it finds a resource in the current Application that is already applied in
            the cluster by another Application.
          '';
        };
      };
      finalSyncOpts = mkOption {
        type = types.listOf types.str;
        default = [];
        internal = true;
      };
    };
    destination = {
      server = mkOption {
        type = types.str;
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
    # If createNamespace is set to `true` we should
    # create one.
    resources = lib.mkIf config.createNamespace {
      namespaces.${config.namespace} = {};
    };

    # Turn all typed resources into standard kubernetes
    # objects that will be written to YAML files.
    objects = with lib;
      flatten (mapAttrsToList (
          _: type:
            mapAttrsToList (_: moduleToAttrs) config.resources.${type.group}.${type.version}.${type.kind}
        )
        config.types);

    annotations = convertCmpOptionsAnnotation config.compareOptions;

    syncPolicy.finalSyncOpts = convertSyncOptionsList config.syncPolicy.syncOptions;
  };
}
