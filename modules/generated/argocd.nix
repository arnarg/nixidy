# This file was generated with nixidy CRD generator, do not edit.
{
  lib,
  options,
  config,
  ...
}:
with lib; let
  hasAttrNotNull = attr: set: hasAttr attr set && !isNull set.${attr};

  attrsToList = values:
    if values != null
    then
      sort (
        a: b:
          if (hasAttrNotNull "_priority" a && hasAttrNotNull "_priority" b)
          then a._priority < b._priority
          else false
      ) (mapAttrsToList (n: v: v) values)
    else values;

  getDefaults = resource: group: version: kind:
    catAttrs "default" (filter (
        default:
          (default.resource == null || default.resource == resource)
          && (default.group == null || default.group == group)
          && (default.version == null || default.version == version)
          && (default.kind == null || default.kind == kind)
      )
      config.defaults);

  types =
    lib.types
    // rec {
      str = mkOptionType {
        name = "str";
        description = "string";
        check = isString;
        merge = mergeEqualOption;
      };

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
              else let
                coerced = coerceFunc val;
              in
                assert finalType.check coerced; coerced;
          in
            finalType.merge loc (map (def: def // {value = coerceVal def.value;}) defs);
          getSubOptions = finalType.getSubOptions;
          getSubModules = finalType.getSubModules;
          substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
          typeMerge = t1: t2: null;
          functor = (defaultFunctor name) // {wrapped = finalType;};
        };
    };

  mkOptionDefault = mkOverride 1001;

  mergeValuesByKey = attrMergeKey: listMergeKeys: values:
    listToAttrs (imap0
      (i: value:
        nameValuePair (
          if hasAttr attrMergeKey value
          then
            if isAttrs value.${attrMergeKey}
            then toString value.${attrMergeKey}.content
            else (toString value.${attrMergeKey})
          else
            # generate merge key for list elements if it's not present
            "__kubenix_list_merge_key_"
            + (concatStringsSep "" (map (
                key:
                  if isAttrs value.${key}
                  then toString value.${key}.content
                  else (toString value.${key})
              )
              listMergeKeys))
        ) (value // {_priority = i;}))
      values);

  submoduleOf = ref:
    types.submodule ({name, ...}: {
      options = definitions."${ref}".options or {};
      config = definitions."${ref}".config or {};
    });

  globalSubmoduleOf = ref:
    types.submodule ({name, ...}: {
      options = config.definitions."${ref}".options or {};
      config = config.definitions."${ref}".config or {};
    });

  submoduleWithMergeOf = ref: mergeKey:
    types.submodule ({name, ...}: let
      convertName = name:
        if definitions."${ref}".options.${mergeKey}.type == types.int
        then toInt name
        else name;
    in {
      options =
        definitions."${ref}".options
        // {
          # position in original array
          _priority = mkOption {
            type = types.nullOr types.int;
            default = null;
          };
        };
      config =
        definitions."${ref}".config
        // {
          ${mergeKey} = mkOverride 1002 (
            # use name as mergeKey only if it is not coming from mergeValuesByKey
            if (!hasPrefix "__kubenix_list_merge_key_" name)
            then convertName name
            else null
          );
        };
    });

  submoduleForDefinition = ref: resource: kind: group: version: let
    apiVersion =
      if group == "core"
      then version
      else "${group}/${version}";
  in
    types.submodule ({name, ...}: {
      imports = getDefaults resource group version kind;
      options = definitions."${ref}".options;
      config = mkMerge [
        definitions."${ref}".config
        {
          kind = mkOptionDefault kind;
          apiVersion = mkOptionDefault apiVersion;

          # metdata.name cannot use option default, due deep config
          metadata.name = mkOptionDefault name;
        }
      ];
    });

  coerceAttrsOfSubmodulesToListByKey = ref: attrMergeKey: listMergeKeys: (
    types.coercedTo
    (types.listOf (submoduleOf ref))
    (mergeValuesByKey attrMergeKey listMergeKeys)
    (types.attrsOf (submoduleWithMergeOf ref attrMergeKey))
  );

  definitions = {
    "argoproj.io.v1alpha1.AppProject" = {
      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = types.nullOr types.str;
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta";
        };
        "spec" = mkOption {
          description = "AppProjectSpec is the specification of an AppProject";
          type = submoduleOf "argoproj.io.v1alpha1.AppProjectSpec";
        };
        "status" = mkOption {
          description = "AppProjectStatus contains status information for AppProject CRs";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.AppProjectStatus");
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectSpec" = {
      options = {
        "clusterResourceBlacklist" = mkOption {
          description = "ClusterResourceBlacklist contains list of blacklisted cluster level resources";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecClusterResourceBlacklist"));
        };
        "clusterResourceWhitelist" = mkOption {
          description = "ClusterResourceWhitelist contains list of whitelisted cluster level resources";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecClusterResourceWhitelist"));
        };
        "description" = mkOption {
          description = "Description contains optional project description";
          type = types.nullOr types.str;
        };
        "destinations" = mkOption {
          description = "Destinations contains list of destinations available for deployment";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.AppProjectSpecDestinations" "name" []);
          apply = attrsToList;
        };
        "namespaceResourceBlacklist" = mkOption {
          description = "NamespaceResourceBlacklist contains list of blacklisted namespace level resources";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecNamespaceResourceBlacklist"));
        };
        "namespaceResourceWhitelist" = mkOption {
          description = "NamespaceResourceWhitelist contains list of whitelisted namespace level resources";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecNamespaceResourceWhitelist"));
        };
        "orphanedResources" = mkOption {
          description = "OrphanedResources specifies if controller should monitor orphaned resources of apps in this project";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecOrphanedResources");
        };
        "permitOnlyProjectScopedClusters" = mkOption {
          description = "PermitOnlyProjectScopedClusters determines whether destinations can only reference clusters which are project-scoped";
          type = types.nullOr types.bool;
        };
        "roles" = mkOption {
          description = "Roles are user defined RBAC roles associated with this project";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.AppProjectSpecRoles" "name" []);
          apply = attrsToList;
        };
        "signatureKeys" = mkOption {
          description = "SignatureKeys contains a list of PGP key IDs that commits in Git must be signed with in order to be allowed for sync";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecSignatureKeys"));
        };
        "sourceNamespaces" = mkOption {
          description = "SourceNamespaces defines the namespaces application resources are allowed to be created in";
          type = types.nullOr (types.listOf types.str);
        };
        "sourceRepos" = mkOption {
          description = "SourceRepos contains list of repository URLs which can be used for deployment";
          type = types.nullOr (types.listOf types.str);
        };
        "syncWindows" = mkOption {
          description = "SyncWindows controls when syncs can be run for apps in this project";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecSyncWindows"));
        };
      };

      config = {
        "clusterResourceBlacklist" = mkOverride 1002 null;
        "clusterResourceWhitelist" = mkOverride 1002 null;
        "description" = mkOverride 1002 null;
        "destinations" = mkOverride 1002 null;
        "namespaceResourceBlacklist" = mkOverride 1002 null;
        "namespaceResourceWhitelist" = mkOverride 1002 null;
        "orphanedResources" = mkOverride 1002 null;
        "permitOnlyProjectScopedClusters" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
        "signatureKeys" = mkOverride 1002 null;
        "sourceNamespaces" = mkOverride 1002 null;
        "sourceRepos" = mkOverride 1002 null;
        "syncWindows" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectSpecClusterResourceBlacklist" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.AppProjectSpecClusterResourceWhitelist" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.AppProjectSpecDestinations" = {
      options = {
        "name" = mkOption {
          description = "Name is an alternate way of specifying the target cluster by its symbolic name. This must be set if Server is not set.";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace specifies the target namespace for the application's resources. The namespace will only be set for namespace-scoped resources that have not set a value for .metadata.namespace";
          type = types.nullOr types.str;
        };
        "server" = mkOption {
          description = "Server specifies the URL of the target cluster's Kubernetes control plane API. This must be set if Name is not set.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "server" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectSpecNamespaceResourceBlacklist" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.AppProjectSpecNamespaceResourceWhitelist" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.AppProjectSpecOrphanedResources" = {
      options = {
        "ignore" = mkOption {
          description = "Ignore contains a list of resources that are to be excluded from orphaned resources monitoring";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.AppProjectSpecOrphanedResourcesIgnore" "name" []);
          apply = attrsToList;
        };
        "warn" = mkOption {
          description = "Warn indicates if warning condition should be created for apps which have orphaned resources";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "ignore" = mkOverride 1002 null;
        "warn" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectSpecOrphanedResourcesIgnore" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectSpecRoles" = {
      options = {
        "description" = mkOption {
          description = "Description is a description of the role";
          type = types.nullOr types.str;
        };
        "groups" = mkOption {
          description = "Groups are a list of OIDC group claims bound to this role";
          type = types.nullOr (types.listOf types.str);
        };
        "jwtTokens" = mkOption {
          description = "JWTTokens are a list of generated JWT tokens bound to this role";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.AppProjectSpecRolesJwtTokens"));
        };
        "name" = mkOption {
          description = "Name is a name for this role";
          type = types.str;
        };
        "policies" = mkOption {
          description = "Policies Stores a list of casbin formatted strings that define access policies for the role in the project";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "description" = mkOverride 1002 null;
        "groups" = mkOverride 1002 null;
        "jwtTokens" = mkOverride 1002 null;
        "policies" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectSpecRolesJwtTokens" = {
      options = {
        "exp" = mkOption {
          description = "";
          type = types.nullOr types.int;
        };
        "iat" = mkOption {
          description = "";
          type = types.int;
        };
        "id" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "exp" = mkOverride 1002 null;
        "id" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectSpecSignatureKeys" = {
      options = {
        "keyID" = mkOption {
          description = "The ID of the key in hexadecimal notation";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.AppProjectSpecSyncWindows" = {
      options = {
        "applications" = mkOption {
          description = "Applications contains a list of applications that the window will apply to";
          type = types.nullOr (types.listOf types.str);
        };
        "clusters" = mkOption {
          description = "Clusters contains a list of clusters that the window will apply to";
          type = types.nullOr (types.listOf types.str);
        };
        "duration" = mkOption {
          description = "Duration is the amount of time the sync window will be open";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind defines if the window allows or blocks syncs";
          type = types.nullOr types.str;
        };
        "manualSync" = mkOption {
          description = "ManualSync enables manual syncs when they would otherwise be blocked";
          type = types.nullOr types.bool;
        };
        "namespaces" = mkOption {
          description = "Namespaces contains a list of namespaces that the window will apply to";
          type = types.nullOr (types.listOf types.str);
        };
        "schedule" = mkOption {
          description = "Schedule is the time the window will begin, specified in cron format";
          type = types.nullOr types.str;
        };
        "timeZone" = mkOption {
          description = "TimeZone of the sync that will be applied to the schedule";
          type = types.nullOr types.str;
        };
      };

      config = {
        "applications" = mkOverride 1002 null;
        "clusters" = mkOverride 1002 null;
        "duration" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "manualSync" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
        "schedule" = mkOverride 1002 null;
        "timeZone" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.AppProjectStatus" = {
      options = {
        "jwtTokensByRole" = mkOption {
          description = "JWTTokensByRole contains a list of JWT tokens issued for a given role";
          type = types.nullOr (types.attrsOf types.attrs);
        };
      };

      config = {
        "jwtTokensByRole" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.Application" = {
      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = types.nullOr types.str;
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta";
        };
        "operation" = mkOption {
          description = "Operation contains information about a requested or running operation";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperation");
        };
        "spec" = mkOption {
          description = "ApplicationSpec represents desired application state. Contains link to repository with application definition and additional parameters link definition revision.";
          type = submoduleOf "argoproj.io.v1alpha1.ApplicationSpec";
        };
        "status" = mkOption {
          description = "ApplicationStatus contains status information for the application";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatus");
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "operation" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperation" = {
      options = {
        "info" = mkOption {
          description = "Info is a list of informational items for this operation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationInfo" "name" []);
          apply = attrsToList;
        };
        "initiatedBy" = mkOption {
          description = "InitiatedBy contains information about who initiated the operations";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationInitiatedBy");
        };
        "retry" = mkOption {
          description = "Retry controls the strategy to apply if a sync fails";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationRetry");
        };
        "sync" = mkOption {
          description = "Sync contains parameters for the operation";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSync");
        };
      };

      config = {
        "info" = mkOverride 1002 null;
        "initiatedBy" = mkOverride 1002 null;
        "retry" = mkOverride 1002 null;
        "sync" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationInfo" = {
      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationOperationInitiatedBy" = {
      options = {
        "automated" = mkOption {
          description = "Automated is set to true if operation was initiated automatically by the application controller.";
          type = types.nullOr types.bool;
        };
        "username" = mkOption {
          description = "Username contains the name of a user who started operation";
          type = types.nullOr types.str;
        };
      };

      config = {
        "automated" = mkOverride 1002 null;
        "username" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationRetry" = {
      options = {
        "backoff" = mkOption {
          description = "Backoff controls how to backoff on subsequent retries of failed syncs";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationRetryBackoff");
        };
        "limit" = mkOption {
          description = "Limit is the maximum number of attempts for retrying a failed sync. If set to 0, no retries will be performed.";
          type = types.nullOr types.int;
        };
      };

      config = {
        "backoff" = mkOverride 1002 null;
        "limit" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationRetryBackoff" = {
      options = {
        "duration" = mkOption {
          description = "Duration is the amount to back off. Default unit is seconds, but could also be a duration (e.g. \"2m\", \"1h\")";
          type = types.nullOr types.str;
        };
        "factor" = mkOption {
          description = "Factor is a factor to multiply the base duration after each failed retry";
          type = types.nullOr types.int;
        };
        "maxDuration" = mkOption {
          description = "MaxDuration is the maximum amount of time allowed for the backoff strategy";
          type = types.nullOr types.str;
        };
      };

      config = {
        "duration" = mkOverride 1002 null;
        "factor" = mkOverride 1002 null;
        "maxDuration" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSync" = {
      options = {
        "dryRun" = mkOption {
          description = "DryRun specifies to perform a `kubectl apply --dry-run` without actually performing the sync";
          type = types.nullOr types.bool;
        };
        "manifests" = mkOption {
          description = "Manifests is an optional field that overrides sync source with a local directory for development";
          type = types.nullOr (types.listOf types.str);
        };
        "prune" = mkOption {
          description = "Prune specifies to delete resources from the cluster that are no longer tracked in git";
          type = types.nullOr types.bool;
        };
        "resources" = mkOption {
          description = "Resources describes which resources shall be part of the sync";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncResources" "name" []);
          apply = attrsToList;
        };
        "revision" = mkOption {
          description = "Revision is the revision (Git) or chart version (Helm) which to sync the application to If omitted, will use the revision specified in app spec.";
          type = types.nullOr types.str;
        };
        "revisions" = mkOption {
          description = "Revisions is the list of revision (Git) or chart version (Helm) which to sync each source in sources field for the application to If omitted, will use the revision specified in app spec.";
          type = types.nullOr (types.listOf types.str);
        };
        "source" = mkOption {
          description = "Source overrides the source definition set in the application. This is typically set in a Rollback operation and is nil during a Sync operation";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSource");
        };
        "sources" = mkOption {
          description = "Sources overrides the source definition set in the application. This is typically set in a Rollback operation and is nil during a Sync operation";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSources"));
        };
        "syncOptions" = mkOption {
          description = "SyncOptions provide per-sync sync-options, e.g. Validate=false";
          type = types.nullOr (types.listOf types.str);
        };
        "syncStrategy" = mkOption {
          description = "SyncStrategy describes how to perform the sync";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSyncStrategy");
        };
      };

      config = {
        "dryRun" = mkOverride 1002 null;
        "manifests" = mkOverride 1002 null;
        "prune" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "revision" = mkOverride 1002 null;
        "revisions" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "sources" = mkOverride 1002 null;
        "syncOptions" = mkOverride 1002 null;
        "syncStrategy" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncResources" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "group" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSource" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourceHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcePlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourceHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourceHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourceKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcePlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcePluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcePluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcePluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcePluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSources" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesPlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesPlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesPluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesPluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesPluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSourcesPluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSyncStrategy" = {
      options = {
        "apply" = mkOption {
          description = "Apply will perform a `kubectl apply` to perform the sync.";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSyncStrategyApply");
        };
        "hook" = mkOption {
          description = "Hook will submit any referenced resources to perform the sync. This is the default strategy";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationOperationSyncSyncStrategyHook");
        };
      };

      config = {
        "apply" = mkOverride 1002 null;
        "hook" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSyncStrategyApply" = {
      options = {
        "force" = mkOption {
          description = "Force indicates whether or not to supply the --force flag to `kubectl apply`. The --force flag deletes and re-create the resource, when PATCH encounters conflict and has retried for 5 times.";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "force" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationOperationSyncSyncStrategyHook" = {
      options = {
        "force" = mkOption {
          description = "Force indicates whether or not to supply the --force flag to `kubectl apply`. The --force flag deletes and re-create the resource, when PATCH encounters conflict and has retried for 5 times.";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "force" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpec" = {
      options = {
        "destination" = mkOption {
          description = "Destination is a reference to the target Kubernetes server and namespace";
          type = submoduleOf "argoproj.io.v1alpha1.ApplicationSpecDestination";
        };
        "ignoreDifferences" = mkOption {
          description = "IgnoreDifferences is a list of resources and their fields which should be ignored during comparison";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecIgnoreDifferences" "name" []);
          apply = attrsToList;
        };
        "info" = mkOption {
          description = "Info contains a list of information (URLs, email addresses, and plain text) that relates to the application";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecInfo" "name" []);
          apply = attrsToList;
        };
        "project" = mkOption {
          description = "Project is a reference to the project this application belongs to. The empty string means that application belongs to the 'default' project.";
          type = types.str;
        };
        "revisionHistoryLimit" = mkOption {
          description = "RevisionHistoryLimit limits the number of items kept in the application's revision history, which is used for informational purposes as well as for rollbacks to previous versions. This should only be changed in exceptional circumstances. Setting to zero will store no history. This will reduce storage used. Increasing will increase the space used to store the history, so we do not recommend increasing it. Default is 10.";
          type = types.nullOr types.int;
        };
        "source" = mkOption {
          description = "Source is a reference to the location of the application's manifests or chart";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSource");
        };
        "sources" = mkOption {
          description = "Sources is a reference to the location of the application's manifests or chart";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSources"));
        };
        "syncPolicy" = mkOption {
          description = "SyncPolicy controls when and how a sync will be performed";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSyncPolicy");
        };
      };

      config = {
        "ignoreDifferences" = mkOverride 1002 null;
        "info" = mkOverride 1002 null;
        "revisionHistoryLimit" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "sources" = mkOverride 1002 null;
        "syncPolicy" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecDestination" = {
      options = {
        "name" = mkOption {
          description = "Name is an alternate way of specifying the target cluster by its symbolic name. This must be set if Server is not set.";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace specifies the target namespace for the application's resources. The namespace will only be set for namespace-scoped resources that have not set a value for .metadata.namespace";
          type = types.nullOr types.str;
        };
        "server" = mkOption {
          description = "Server specifies the URL of the target cluster's Kubernetes control plane API. This must be set if Name is not set.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "server" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecIgnoreDifferences" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "jqPathExpressions" = mkOption {
          description = "";
          type = types.nullOr (types.listOf types.str);
        };
        "jsonPointers" = mkOption {
          description = "";
          type = types.nullOr (types.listOf types.str);
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
        "managedFieldsManagers" = mkOption {
          description = "ManagedFieldsManagers is a list of trusted managers. Fields mutated by those managers will take precedence over the desired state defined in the SCM and won't be displayed in diffs";
          type = types.nullOr (types.listOf types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "group" = mkOverride 1002 null;
        "jqPathExpressions" = mkOverride 1002 null;
        "jsonPointers" = mkOverride 1002 null;
        "managedFieldsManagers" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecInfo" = {
      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationSpecSource" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourceDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourceHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourceKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcePlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourceDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourceDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourceDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourceHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourceHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourceKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourceKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourceKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourceKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcePlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcePluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcePluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcePluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcePluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSources" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcesHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcesPlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcesHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcesHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesPlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcesPluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationSpecSourcesPluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesPluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationSpecSourcesPluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSyncPolicy" = {
      options = {
        "automated" = mkOption {
          description = "Automated will keep an application synced to the target revision";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyAutomated");
        };
        "managedNamespaceMetadata" = mkOption {
          description = "ManagedNamespaceMetadata controls metadata in the given namespace (if CreateNamespace=true)";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyManagedNamespaceMetadata");
        };
        "retry" = mkOption {
          description = "Retry controls failed sync retry behavior";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyRetry");
        };
        "syncOptions" = mkOption {
          description = "Options allow you to specify whole app sync-options";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "automated" = mkOverride 1002 null;
        "managedNamespaceMetadata" = mkOverride 1002 null;
        "retry" = mkOverride 1002 null;
        "syncOptions" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyAutomated" = {
      options = {
        "allowEmpty" = mkOption {
          description = "AllowEmpty allows apps have zero live resources (default: false)";
          type = types.nullOr types.bool;
        };
        "prune" = mkOption {
          description = "Prune specifies whether to delete resources from the cluster that are not found in the sources anymore as part of automated sync (default: false)";
          type = types.nullOr types.bool;
        };
        "selfHeal" = mkOption {
          description = "SelfHeal specifies whether to revert resources back to their desired state upon modification in the cluster (default: false)";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "allowEmpty" = mkOverride 1002 null;
        "prune" = mkOverride 1002 null;
        "selfHeal" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyManagedNamespaceMetadata" = {
      options = {
        "annotations" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.str);
        };
        "labels" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyRetry" = {
      options = {
        "backoff" = mkOption {
          description = "Backoff controls how to backoff on subsequent retries of failed syncs";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyRetryBackoff");
        };
        "limit" = mkOption {
          description = "Limit is the maximum number of attempts for retrying a failed sync. If set to 0, no retries will be performed.";
          type = types.nullOr types.int;
        };
      };

      config = {
        "backoff" = mkOverride 1002 null;
        "limit" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationSpecSyncPolicyRetryBackoff" = {
      options = {
        "duration" = mkOption {
          description = "Duration is the amount to back off. Default unit is seconds, but could also be a duration (e.g. \"2m\", \"1h\")";
          type = types.nullOr types.str;
        };
        "factor" = mkOption {
          description = "Factor is a factor to multiply the base duration after each failed retry";
          type = types.nullOr types.int;
        };
        "maxDuration" = mkOption {
          description = "MaxDuration is the maximum amount of time allowed for the backoff strategy";
          type = types.nullOr types.str;
        };
      };

      config = {
        "duration" = mkOverride 1002 null;
        "factor" = mkOverride 1002 null;
        "maxDuration" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatus" = {
      options = {
        "conditions" = mkOption {
          description = "Conditions is a list of currently observed application conditions";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusConditions"));
        };
        "controllerNamespace" = mkOption {
          description = "ControllerNamespace indicates the namespace in which the application controller is located";
          type = types.nullOr types.str;
        };
        "health" = mkOption {
          description = "Health contains information about the application's current health status";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHealth");
        };
        "history" = mkOption {
          description = "History contains information about the application's sync history";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistory"));
        };
        "observedAt" = mkOption {
          description = "ObservedAt indicates when the application state was updated without querying latest git state Deprecated: controller no longer updates ObservedAt field";
          type = types.nullOr types.str;
        };
        "operationState" = mkOption {
          description = "OperationState contains information about any ongoing operations, such as a sync";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationState");
        };
        "reconciledAt" = mkOption {
          description = "ReconciledAt indicates when the application state was reconciled using the latest git version";
          type = types.nullOr types.str;
        };
        "resourceHealthSource" = mkOption {
          description = "ResourceHealthSource indicates where the resource health status is stored: inline if not set or appTree";
          type = types.nullOr types.str;
        };
        "resources" = mkOption {
          description = "Resources is a list of Kubernetes resources managed by this application";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusResources" "name" []);
          apply = attrsToList;
        };
        "sourceType" = mkOption {
          description = "SourceType specifies the type of this application";
          type = types.nullOr types.str;
        };
        "sourceTypes" = mkOption {
          description = "SourceTypes specifies the type of the sources included in the application";
          type = types.nullOr (types.listOf types.str);
        };
        "summary" = mkOption {
          description = "Summary contains a list of URLs and container images used by this application";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSummary");
        };
        "sync" = mkOption {
          description = "Sync contains information about the application's current sync status";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSync");
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "controllerNamespace" = mkOverride 1002 null;
        "health" = mkOverride 1002 null;
        "history" = mkOverride 1002 null;
        "observedAt" = mkOverride 1002 null;
        "operationState" = mkOverride 1002 null;
        "reconciledAt" = mkOverride 1002 null;
        "resourceHealthSource" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "sourceType" = mkOverride 1002 null;
        "sourceTypes" = mkOverride 1002 null;
        "summary" = mkOverride 1002 null;
        "sync" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusConditions" = {
      options = {
        "lastTransitionTime" = mkOption {
          description = "LastTransitionTime is the time the condition was last observed";
          type = types.nullOr types.str;
        };
        "message" = mkOption {
          description = "Message contains human-readable message indicating details about condition";
          type = types.str;
        };
        "type" = mkOption {
          description = "Type is an application condition type";
          type = types.str;
        };
      };

      config = {
        "lastTransitionTime" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHealth" = {
      options = {
        "message" = mkOption {
          description = "Message is a human-readable informational message describing the health status";
          type = types.nullOr types.str;
        };
        "status" = mkOption {
          description = "Status holds the status code of the application or resource";
          type = types.nullOr types.str;
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistory" = {
      options = {
        "deployStartedAt" = mkOption {
          description = "DeployStartedAt holds the time the sync operation started";
          type = types.nullOr types.str;
        };
        "deployedAt" = mkOption {
          description = "DeployedAt holds the time the sync operation completed";
          type = types.str;
        };
        "id" = mkOption {
          description = "ID is an auto incrementing identifier of the RevisionHistory";
          type = types.int;
        };
        "initiatedBy" = mkOption {
          description = "InitiatedBy contains information about who initiated the operations";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistoryInitiatedBy");
        };
        "revision" = mkOption {
          description = "Revision holds the revision the sync was performed against";
          type = types.nullOr types.str;
        };
        "revisions" = mkOption {
          description = "Revisions holds the revision of each source in sources field the sync was performed against";
          type = types.nullOr (types.listOf types.str);
        };
        "source" = mkOption {
          description = "Source is a reference to the application source used for the sync operation";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySource");
        };
        "sources" = mkOption {
          description = "Sources is a reference to the application sources used for the sync operation";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySources"));
        };
      };

      config = {
        "deployStartedAt" = mkOverride 1002 null;
        "initiatedBy" = mkOverride 1002 null;
        "revision" = mkOverride 1002 null;
        "revisions" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "sources" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistoryInitiatedBy" = {
      options = {
        "automated" = mkOption {
          description = "Automated is set to true if operation was initiated automatically by the application controller.";
          type = types.nullOr types.bool;
        };
        "username" = mkOption {
          description = "Username contains the name of a user who started operation";
          type = types.nullOr types.str;
        };
      };

      config = {
        "automated" = mkOverride 1002 null;
        "username" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySource" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourceHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcePlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourceHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourceHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourceKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcePlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcePluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcePluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcePluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcePluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySources" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesPlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesPlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesPluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesPluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesPluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusHistorySourcesPluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationState" = {
      options = {
        "finishedAt" = mkOption {
          description = "FinishedAt contains time of operation completion";
          type = types.nullOr types.str;
        };
        "message" = mkOption {
          description = "Message holds any pertinent messages when attempting to perform operation (typically errors).";
          type = types.nullOr types.str;
        };
        "operation" = mkOption {
          description = "Operation is the original requested operation";
          type = submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperation";
        };
        "phase" = mkOption {
          description = "Phase is the current phase of the operation";
          type = types.str;
        };
        "retryCount" = mkOption {
          description = "RetryCount contains time of operation retries";
          type = types.nullOr types.int;
        };
        "startedAt" = mkOption {
          description = "StartedAt contains time of operation start";
          type = types.str;
        };
        "syncResult" = mkOption {
          description = "SyncResult is the result of a Sync operation";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResult");
        };
      };

      config = {
        "finishedAt" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "retryCount" = mkOverride 1002 null;
        "syncResult" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperation" = {
      options = {
        "info" = mkOption {
          description = "Info is a list of informational items for this operation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationInfo" "name" []);
          apply = attrsToList;
        };
        "initiatedBy" = mkOption {
          description = "InitiatedBy contains information about who initiated the operations";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationInitiatedBy");
        };
        "retry" = mkOption {
          description = "Retry controls the strategy to apply if a sync fails";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationRetry");
        };
        "sync" = mkOption {
          description = "Sync contains parameters for the operation";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSync");
        };
      };

      config = {
        "info" = mkOverride 1002 null;
        "initiatedBy" = mkOverride 1002 null;
        "retry" = mkOverride 1002 null;
        "sync" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationInfo" = {
      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationInitiatedBy" = {
      options = {
        "automated" = mkOption {
          description = "Automated is set to true if operation was initiated automatically by the application controller.";
          type = types.nullOr types.bool;
        };
        "username" = mkOption {
          description = "Username contains the name of a user who started operation";
          type = types.nullOr types.str;
        };
      };

      config = {
        "automated" = mkOverride 1002 null;
        "username" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationRetry" = {
      options = {
        "backoff" = mkOption {
          description = "Backoff controls how to backoff on subsequent retries of failed syncs";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationRetryBackoff");
        };
        "limit" = mkOption {
          description = "Limit is the maximum number of attempts for retrying a failed sync. If set to 0, no retries will be performed.";
          type = types.nullOr types.int;
        };
      };

      config = {
        "backoff" = mkOverride 1002 null;
        "limit" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationRetryBackoff" = {
      options = {
        "duration" = mkOption {
          description = "Duration is the amount to back off. Default unit is seconds, but could also be a duration (e.g. \"2m\", \"1h\")";
          type = types.nullOr types.str;
        };
        "factor" = mkOption {
          description = "Factor is a factor to multiply the base duration after each failed retry";
          type = types.nullOr types.int;
        };
        "maxDuration" = mkOption {
          description = "MaxDuration is the maximum amount of time allowed for the backoff strategy";
          type = types.nullOr types.str;
        };
      };

      config = {
        "duration" = mkOverride 1002 null;
        "factor" = mkOverride 1002 null;
        "maxDuration" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSync" = {
      options = {
        "dryRun" = mkOption {
          description = "DryRun specifies to perform a `kubectl apply --dry-run` without actually performing the sync";
          type = types.nullOr types.bool;
        };
        "manifests" = mkOption {
          description = "Manifests is an optional field that overrides sync source with a local directory for development";
          type = types.nullOr (types.listOf types.str);
        };
        "prune" = mkOption {
          description = "Prune specifies to delete resources from the cluster that are no longer tracked in git";
          type = types.nullOr types.bool;
        };
        "resources" = mkOption {
          description = "Resources describes which resources shall be part of the sync";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncResources" "name" []);
          apply = attrsToList;
        };
        "revision" = mkOption {
          description = "Revision is the revision (Git) or chart version (Helm) which to sync the application to If omitted, will use the revision specified in app spec.";
          type = types.nullOr types.str;
        };
        "revisions" = mkOption {
          description = "Revisions is the list of revision (Git) or chart version (Helm) which to sync each source in sources field for the application to If omitted, will use the revision specified in app spec.";
          type = types.nullOr (types.listOf types.str);
        };
        "source" = mkOption {
          description = "Source overrides the source definition set in the application. This is typically set in a Rollback operation and is nil during a Sync operation";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSource");
        };
        "sources" = mkOption {
          description = "Sources overrides the source definition set in the application. This is typically set in a Rollback operation and is nil during a Sync operation";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSources"));
        };
        "syncOptions" = mkOption {
          description = "SyncOptions provide per-sync sync-options, e.g. Validate=false";
          type = types.nullOr (types.listOf types.str);
        };
        "syncStrategy" = mkOption {
          description = "SyncStrategy describes how to perform the sync";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSyncStrategy");
        };
      };

      config = {
        "dryRun" = mkOverride 1002 null;
        "manifests" = mkOverride 1002 null;
        "prune" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "revision" = mkOverride 1002 null;
        "revisions" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "sources" = mkOverride 1002 null;
        "syncOptions" = mkOverride 1002 null;
        "syncStrategy" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncResources" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "group" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSource" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcePlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourceKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcePlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcePluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcePluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcePluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcePluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSources" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesPlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesPlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesPluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesPluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesPluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSourcesPluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSyncStrategy" = {
      options = {
        "apply" = mkOption {
          description = "Apply will perform a `kubectl apply` to perform the sync.";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSyncStrategyApply");
        };
        "hook" = mkOption {
          description = "Hook will submit any referenced resources to perform the sync. This is the default strategy";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSyncStrategyHook");
        };
      };

      config = {
        "apply" = mkOverride 1002 null;
        "hook" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSyncStrategyApply" = {
      options = {
        "force" = mkOption {
          description = "Force indicates whether or not to supply the --force flag to `kubectl apply`. The --force flag deletes and re-create the resource, when PATCH encounters conflict and has retried for 5 times.";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "force" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateOperationSyncSyncStrategyHook" = {
      options = {
        "force" = mkOption {
          description = "Force indicates whether or not to supply the --force flag to `kubectl apply`. The --force flag deletes and re-create the resource, when PATCH encounters conflict and has retried for 5 times.";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "force" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResult" = {
      options = {
        "managedNamespaceMetadata" = mkOption {
          description = "ManagedNamespaceMetadata contains the current sync state of managed namespace metadata";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultManagedNamespaceMetadata");
        };
        "resources" = mkOption {
          description = "Resources contains a list of sync result items for each individual resource in a sync operation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultResources" "name" []);
          apply = attrsToList;
        };
        "revision" = mkOption {
          description = "Revision holds the revision this sync operation was performed to";
          type = types.str;
        };
        "revisions" = mkOption {
          description = "Revisions holds the revision this sync operation was performed for respective indexed source in sources field";
          type = types.nullOr (types.listOf types.str);
        };
        "source" = mkOption {
          description = "Source records the application source information of the sync, used for comparing auto-sync";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSource");
        };
        "sources" = mkOption {
          description = "Source records the application source information of the sync, used for comparing auto-sync";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSources"));
        };
      };

      config = {
        "managedNamespaceMetadata" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "revisions" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "sources" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultManagedNamespaceMetadata" = {
      options = {
        "annotations" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.str);
        };
        "labels" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultResources" = {
      options = {
        "group" = mkOption {
          description = "Group specifies the API group of the resource";
          type = types.str;
        };
        "hookPhase" = mkOption {
          description = "HookPhase contains the state of any operation associated with this resource OR hook This can also contain values for non-hook resources.";
          type = types.nullOr types.str;
        };
        "hookType" = mkOption {
          description = "HookType specifies the type of the hook. Empty for non-hook resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind specifies the API kind of the resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "Message contains an informational or error message for the last sync OR operation";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "Name specifies the name of the resource";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace specifies the target namespace of the resource";
          type = types.str;
        };
        "status" = mkOption {
          description = "Status holds the final result of the sync. Will be empty if the resources is yet to be applied/pruned and is always zero-value for hooks";
          type = types.nullOr types.str;
        };
        "syncPhase" = mkOption {
          description = "SyncPhase indicates the particular phase of the sync that this result was acquired in";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "Version specifies the API version of the resource";
          type = types.str;
        };
      };

      config = {
        "hookPhase" = mkOverride 1002 null;
        "hookType" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "syncPhase" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSource" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcePlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourceKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcePlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcePluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcePluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcePluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcePluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSources" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesPlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesPlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesPluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesPluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesPluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusOperationStateSyncResultSourcesPluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusResources" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "health" = mkOption {
          description = "HealthStatus contains information about the currently observed health state of an application or resource";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusResourcesHealth");
        };
        "hook" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "requiresPruning" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "status" = mkOption {
          description = "SyncStatusCode is a type which represents possible comparison results";
          type = types.nullOr types.str;
        };
        "syncWave" = mkOption {
          description = "";
          type = types.nullOr types.int;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "group" = mkOverride 1002 null;
        "health" = mkOverride 1002 null;
        "hook" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "requiresPruning" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "syncWave" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusResourcesHealth" = {
      options = {
        "message" = mkOption {
          description = "Message is a human-readable informational message describing the health status";
          type = types.nullOr types.str;
        };
        "status" = mkOption {
          description = "Status holds the status code of the application or resource";
          type = types.nullOr types.str;
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSummary" = {
      options = {
        "externalURLs" = mkOption {
          description = "ExternalURLs holds all external URLs of application child resources.";
          type = types.nullOr (types.listOf types.str);
        };
        "images" = mkOption {
          description = "Images holds all images of application child resources.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "externalURLs" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSync" = {
      options = {
        "comparedTo" = mkOption {
          description = "ComparedTo contains information about what has been compared";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedTo");
        };
        "revision" = mkOption {
          description = "Revision contains information about the revision the comparison has been performed to";
          type = types.nullOr types.str;
        };
        "revisions" = mkOption {
          description = "Revisions contains information about the revisions of multiple sources the comparison has been performed to";
          type = types.nullOr (types.listOf types.str);
        };
        "status" = mkOption {
          description = "Status is the sync state of the comparison";
          type = types.str;
        };
      };

      config = {
        "comparedTo" = mkOverride 1002 null;
        "revision" = mkOverride 1002 null;
        "revisions" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedTo" = {
      options = {
        "destination" = mkOption {
          description = "Destination is a reference to the application's destination used for comparison";
          type = submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToDestination";
        };
        "ignoreDifferences" = mkOption {
          description = "IgnoreDifferences is a reference to the application's ignored differences used for comparison";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToIgnoreDifferences" "name" []);
          apply = attrsToList;
        };
        "source" = mkOption {
          description = "Source is a reference to the application's source used for comparison";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSource");
        };
        "sources" = mkOption {
          description = "Sources is a reference to the application's multiple sources used for comparison";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSources"));
        };
      };

      config = {
        "ignoreDifferences" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "sources" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToDestination" = {
      options = {
        "name" = mkOption {
          description = "Name is an alternate way of specifying the target cluster by its symbolic name. This must be set if Server is not set.";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace specifies the target namespace for the application's resources. The namespace will only be set for namespace-scoped resources that have not set a value for .metadata.namespace";
          type = types.nullOr types.str;
        };
        "server" = mkOption {
          description = "Server specifies the URL of the target cluster's Kubernetes control plane API. This must be set if Name is not set.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "server" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToIgnoreDifferences" = {
      options = {
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "jqPathExpressions" = mkOption {
          description = "";
          type = types.nullOr (types.listOf types.str);
        };
        "jsonPointers" = mkOption {
          description = "";
          type = types.nullOr (types.listOf types.str);
        };
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
        "managedFieldsManagers" = mkOption {
          description = "ManagedFieldsManagers is a list of trusted managers. Fields mutated by those managers will take precedence over the desired state defined in the SCM and won't be displayed in diffs";
          type = types.nullOr (types.listOf types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "group" = mkOverride 1002 null;
        "jqPathExpressions" = mkOverride 1002 null;
        "jsonPointers" = mkOverride 1002 null;
        "managedFieldsManagers" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSource" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcePlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourceKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcePlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcePluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcePluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcePluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcePluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSources" = {
      options = {
        "chart" = mkOption {
          description = "Chart is a Helm chart name, and must be specified for applications sourced from a Helm repo.";
          type = types.nullOr types.str;
        };
        "directory" = mkOption {
          description = "Directory holds path/directory specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectory");
        };
        "helm" = mkOption {
          description = "Helm holds helm specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesHelm");
        };
        "kustomize" = mkOption {
          description = "Kustomize holds kustomize specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomize");
        };
        "path" = mkOption {
          description = "Path is a directory path within the Git repository, and is only valid for applications sourced from Git.";
          type = types.nullOr types.str;
        };
        "plugin" = mkOption {
          description = "Plugin holds config management plugin specific options";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesPlugin");
        };
        "ref" = mkOption {
          description = "Ref is reference to another source within sources field. This field will not be used if used with a `source` tag.";
          type = types.nullOr types.str;
        };
        "repoURL" = mkOption {
          description = "RepoURL is the URL to the repository (Git or Helm) that contains the application manifests";
          type = types.str;
        };
        "targetRevision" = mkOption {
          description = "TargetRevision defines the revision of the source to sync the application to. In case of Git, this can be commit, tag, or branch. If omitted, will equal to HEAD. In case of Helm, this is a semver tag for the Chart's version.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "chart" = mkOverride 1002 null;
        "directory" = mkOverride 1002 null;
        "helm" = mkOverride 1002 null;
        "kustomize" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "plugin" = mkOverride 1002 null;
        "ref" = mkOverride 1002 null;
        "targetRevision" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectory" = {
      options = {
        "exclude" = mkOption {
          description = "Exclude contains a glob pattern to match paths against that should be explicitly excluded from being used during manifest generation";
          type = types.nullOr types.str;
        };
        "include" = mkOption {
          description = "Include contains a glob pattern to match paths against that should be explicitly included during manifest generation";
          type = types.nullOr types.str;
        };
        "jsonnet" = mkOption {
          description = "Jsonnet holds options specific to Jsonnet";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectoryJsonnet");
        };
        "recurse" = mkOption {
          description = "Recurse specifies whether to scan a directory recursively for manifests";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "exclude" = mkOverride 1002 null;
        "include" = mkOverride 1002 null;
        "jsonnet" = mkOverride 1002 null;
        "recurse" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectoryJsonnet" = {
      options = {
        "extVars" = mkOption {
          description = "ExtVars is a list of Jsonnet External Variables";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectoryJsonnetExtVars" "name" []);
          apply = attrsToList;
        };
        "libs" = mkOption {
          description = "Additional library search dirs";
          type = types.nullOr (types.listOf types.str);
        };
        "tlas" = mkOption {
          description = "TLAS is a list of Jsonnet Top-level Arguments";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectoryJsonnetTlas" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "extVars" = mkOverride 1002 null;
        "libs" = mkOverride 1002 null;
        "tlas" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectoryJsonnetExtVars" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesDirectoryJsonnetTlas" = {
      options = {
        "code" = mkOption {
          description = "";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "value" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "code" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesHelm" = {
      options = {
        "fileParameters" = mkOption {
          description = "FileParameters are file parameters to the helm template";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesHelmFileParameters" "name" []);
          apply = attrsToList;
        };
        "ignoreMissingValueFiles" = mkOption {
          description = "IgnoreMissingValueFiles prevents helm template from failing when valueFiles do not exist locally by not appending them to helm template --values";
          type = types.nullOr types.bool;
        };
        "parameters" = mkOption {
          description = "Parameters is a list of Helm parameters which are passed to the helm template command upon manifest generation";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesHelmParameters" "name" []);
          apply = attrsToList;
        };
        "passCredentials" = mkOption {
          description = "PassCredentials pass credentials to all domains (Helm's --pass-credentials)";
          type = types.nullOr types.bool;
        };
        "releaseName" = mkOption {
          description = "ReleaseName is the Helm release name to use. If omitted it will use the application name";
          type = types.nullOr types.str;
        };
        "skipCrds" = mkOption {
          description = "SkipCrds skips custom resource definition installation step (Helm's --skip-crds)";
          type = types.nullOr types.bool;
        };
        "valueFiles" = mkOption {
          description = "ValuesFiles is a list of Helm value files to use when generating a template";
          type = types.nullOr (types.listOf types.str);
        };
        "values" = mkOption {
          description = "Values specifies Helm values to be passed to helm template, typically defined as a block. ValuesObject takes precedence over Values, so use one or the other.";
          type = types.nullOr types.str;
        };
        "valuesObject" = mkOption {
          description = "ValuesObject specifies Helm values to be passed to helm template, defined as a map. This takes precedence over Values.";
          type = types.nullOr types.attrs;
        };
        "version" = mkOption {
          description = "Version is the Helm version to use for templating (\"3\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "fileParameters" = mkOverride 1002 null;
        "ignoreMissingValueFiles" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "passCredentials" = mkOverride 1002 null;
        "releaseName" = mkOverride 1002 null;
        "skipCrds" = mkOverride 1002 null;
        "valueFiles" = mkOverride 1002 null;
        "values" = mkOverride 1002 null;
        "valuesObject" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesHelmFileParameters" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "Path is the path to the file containing the values for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesHelmParameters" = {
      options = {
        "forceString" = mkOption {
          description = "ForceString determines whether to tell Helm to interpret booleans and numbers as strings";
          type = types.nullOr types.bool;
        };
        "name" = mkOption {
          description = "Name is the name of the Helm parameter";
          type = types.nullOr types.str;
        };
        "value" = mkOption {
          description = "Value is the value for the Helm parameter";
          type = types.nullOr types.str;
        };
      };

      config = {
        "forceString" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomize" = {
      options = {
        "commonAnnotations" = mkOption {
          description = "CommonAnnotations is a list of additional annotations to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "commonAnnotationsEnvsubst" = mkOption {
          description = "CommonAnnotationsEnvsubst specifies whether to apply env variables substitution for annotation values";
          type = types.nullOr types.bool;
        };
        "commonLabels" = mkOption {
          description = "CommonLabels is a list of additional labels to add to rendered manifests";
          type = types.nullOr (types.attrsOf types.str);
        };
        "components" = mkOption {
          description = "Components specifies a list of kustomize components to add to the kustomization before building";
          type = types.nullOr (types.listOf types.str);
        };
        "forceCommonAnnotations" = mkOption {
          description = "ForceCommonAnnotations specifies whether to force applying common annotations to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "forceCommonLabels" = mkOption {
          description = "ForceCommonLabels specifies whether to force applying common labels to resources for Kustomize apps";
          type = types.nullOr types.bool;
        };
        "images" = mkOption {
          description = "Images is a list of Kustomize image override specifications";
          type = types.nullOr (types.listOf types.str);
        };
        "labelWithoutSelector" = mkOption {
          description = "LabelWithoutSelector specifies whether to apply common labels to resource selectors or not";
          type = types.nullOr types.bool;
        };
        "namePrefix" = mkOption {
          description = "NamePrefix is a prefix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "nameSuffix" = mkOption {
          description = "NameSuffix is a suffix appended to resources for Kustomize apps";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace sets the namespace that Kustomize adds to all resources";
          type = types.nullOr types.str;
        };
        "patches" = mkOption {
          description = "Patches is a list of Kustomize patches";
          type = types.nullOr (types.listOf (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomizePatches"));
        };
        "replicas" = mkOption {
          description = "Replicas is a list of Kustomize Replicas override specifications";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomizeReplicas" "name" []);
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version controls which version of Kustomize to use for rendering manifests";
          type = types.nullOr types.str;
        };
      };

      config = {
        "commonAnnotations" = mkOverride 1002 null;
        "commonAnnotationsEnvsubst" = mkOverride 1002 null;
        "commonLabels" = mkOverride 1002 null;
        "components" = mkOverride 1002 null;
        "forceCommonAnnotations" = mkOverride 1002 null;
        "forceCommonLabels" = mkOverride 1002 null;
        "images" = mkOverride 1002 null;
        "labelWithoutSelector" = mkOverride 1002 null;
        "namePrefix" = mkOverride 1002 null;
        "nameSuffix" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "patches" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomizePatches" = {
      options = {
        "options" = mkOption {
          description = "";
          type = types.nullOr (types.attrsOf types.bool);
        };
        "patch" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "path" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "target" = mkOption {
          description = "";
          type = types.nullOr (submoduleOf "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomizePatchesTarget");
        };
      };

      config = {
        "options" = mkOverride 1002 null;
        "patch" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "target" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomizePatchesTarget" = {
      options = {
        "annotationSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "group" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "labelSelector" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotationSelector" = mkOverride 1002 null;
        "group" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "labelSelector" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesKustomizeReplicas" = {
      options = {
        "count" = mkOption {
          description = "Number of replicas";
          type = types.int;
        };
        "name" = mkOption {
          description = "Name of Deployment or StatefulSet";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesPlugin" = {
      options = {
        "env" = mkOption {
          description = "Env is a list of environment variable entries";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesPluginEnv" "name" []);
          apply = attrsToList;
        };
        "name" = mkOption {
          description = "";
          type = types.nullOr types.str;
        };
        "parameters" = mkOption {
          description = "";
          type = types.nullOr (coerceAttrsOfSubmodulesToListByKey "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesPluginParameters" "name" []);
          apply = attrsToList;
        };
      };

      config = {
        "env" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesPluginEnv" = {
      options = {
        "name" = mkOption {
          description = "Name is the name of the variable, usually expressed in uppercase";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value is the value of the variable";
          type = types.str;
        };
      };

      config = {};
    };
    "argoproj.io.v1alpha1.ApplicationStatusSyncComparedToSourcesPluginParameters" = {
      options = {
        "array" = mkOption {
          description = "Array is the value of an array type parameter.";
          type = types.nullOr (types.listOf types.str);
        };
        "map" = mkOption {
          description = "Map is the value of a map type parameter.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name identifying a parameter.";
          type = types.nullOr types.str;
        };
        "string" = mkOption {
          description = "String_ is the value of a string type parameter.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "array" = mkOverride 1002 null;
        "map" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "string" = mkOverride 1002 null;
      };
    };
  };
in {
  # all resource versions
  options = {
    resources =
      {
        "argoproj.io"."v1alpha1"."AppProject" = mkOption {
          description = "AppProject provides a logical grouping of applications, providing controls for: * where the apps may deploy to (cluster whitelist) * what may be deployed (repository whitelist, resource whitelist/blacklist) * who can access these applications (roles, OIDC group claims bindings) * and what they can do (RBAC policies) * automation access to these roles (JWT tokens)";
          type = types.attrsOf (submoduleForDefinition "argoproj.io.v1alpha1.AppProject" "appprojects" "AppProject" "argoproj.io" "v1alpha1");
          default = {};
        };
        "argoproj.io"."v1alpha1"."Application" = mkOption {
          description = "Application is a definition of Application resource.";
          type = types.attrsOf (submoduleForDefinition "argoproj.io.v1alpha1.Application" "applications" "Application" "argoproj.io" "v1alpha1");
          default = {};
        };
      }
      // {
        "appprojects" = mkOption {
          description = "AppProject provides a logical grouping of applications, providing controls for: * where the apps may deploy to (cluster whitelist) * what may be deployed (repository whitelist, resource whitelist/blacklist) * who can access these applications (roles, OIDC group claims bindings) * and what they can do (RBAC policies) * automation access to these roles (JWT tokens)";
          type = types.attrsOf (submoduleForDefinition "argoproj.io.v1alpha1.AppProject" "appprojects" "AppProject" "argoproj.io" "v1alpha1");
          default = {};
        };
        "applications" = mkOption {
          description = "Application is a definition of Application resource.";
          type = types.attrsOf (submoduleForDefinition "argoproj.io.v1alpha1.Application" "applications" "Application" "argoproj.io" "v1alpha1");
          default = {};
        };
      };
  };

  config = {
    # expose resource definitions
    inherit definitions;

    # register resource types
    types = [
      {
        name = "appprojects";
        group = "argoproj.io";
        version = "v1alpha1";
        kind = "AppProject";
        attrName = "appprojects";
      }
      {
        name = "applications";
        group = "argoproj.io";
        version = "v1alpha1";
        kind = "Application";
        attrName = "applications";
      }
    ];

    resources = {
      "argoproj.io"."v1alpha1"."AppProject" =
        mkAliasDefinitions options.resources."appprojects";
      "argoproj.io"."v1alpha1"."Application" =
        mkAliasDefinitions options.resources."applications";
    };

    defaults = [
      {
        group = "argoproj.io";
        version = "v1alpha1";
        kind = "AppProject";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "argoproj.io";
        version = "v1alpha1";
        kind = "Application";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
    ];
  };
}
