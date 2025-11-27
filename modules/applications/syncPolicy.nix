{
  lib,
  nixidyDefaults,
}:
with lib;
{
  autoSync = {
    enable = mkOption {
      type = types.bool;
      default = nixidyDefaults.syncPolicy.autoSync.enable;
      defaultText = literalExpression "config.nixidy.defaults.syncPolicy.autoSync.enable";
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
  managedNamespaceMetadata = mkOption {
    type = types.nullOr (
      types.submodule {
        options = {
          annotations = mkOption {
            type = types.nullOr (types.attrsOf types.str);
            description = ''
              Annotations to add to the ArgoCD managed namespace.
            '';
            default = null;
          };
          labels = mkOption {
            type = types.nullOr (types.attrsOf types.str);
            description = ''
              Label to add to the ArgoCD managed namespace.
            '';
            default = null;
          };
        };

        config = { };
      }
    );
    default = null;
    description = ''
      ArgoCD Managed namespace metadata.
    '';
  };
  retry = mkOption {
    type = types.nullOr (
      types.submodule {
        options = {
          backoff = mkOption {
            type = types.nullOr (
              types.submodule {
                options = {
                  duration = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                  };
                  factor = mkOption {
                    type = types.nullOr types.int;
                    default = null;
                  };
                  maxDuration = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                  };
                };

                config = { };
              }
            );

            default = null;
          };

          limit = mkOption {
            type = (types.nullOr types.int);
            default = null;
          };
        };

        config = { };
      }
    );

    default = null;
    description = ''
      ArgoCD retry syncPolicy.
    '';
  };
  syncOptions = {
    applyOutOfSyncOnly = mkOption {
      type = types.bool;
      default = false;
      apply = val: if val then "ApplyOutOfSyncOnly=true" else null;
      description = ''
        Currently when syncing using auto sync Argo CD applies every object in the application.
        For applications containing thousands of objects this takes quite a long time and puts undue pressure on the api server.
        Turning on selective sync option which will sync only out-of-sync resources.
      '';
    };
    createNamespace = mkOption {
      type = types.bool;
      default = false;
      apply = val: if val then "CreateNamespace=true" else null;
      description = ''
        Namespace Auto-Creation ensures that namespace specified as the
        application destination exists in the destination cluster.
      '';
    };
    pruneLast = mkOption {
      type = types.bool;
      default = false;
      apply = val: if val then "PruneLast=true" else null;
      description = ''
        This feature is to allow the ability for resource pruning to happen as a final, implicit wave of a sync operation,
        after the other resources have been deployed and become healthy, and after all other waves completed successfully.
      '';
    };
    replace = mkOption {
      type = types.bool;
      default = false;
      apply = val: if val then "Replace=true" else null;
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
      apply = val: if val then "ServerSideApply=true" else null;
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
      apply = val: if val then "FailOnSharedResource=true" else null;
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
    default = [ ];
    internal = true;
  };
}
