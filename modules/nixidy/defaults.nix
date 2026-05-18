{ lib, ... }:
{
  options.nixidy.defaults = with lib; {
    helm = {
      extraOpts = mkOption {
        type = with types; listOf str;
        default = [ ];
        example = [ "--no-hooks" ];
        description = ''
          The default extra options to pass to `helm template` that is run
          when rendering the helm chart, applies to all applications.
        '';
      };
      transformer = mkOption {
        type = with types; functionTo (listOf (attrsOf anything));
        default = res: res;
        defaultText = literalExpression "res: res";
        example = literalExpression ''
          map (lib.kube.removeLabels ["helm.sh/chart"])
        '';
        description = ''
          Function that will be applied to the list of rendered manifests after the helm templating.
          This option applies to all helm releases in all applications unless explicitly specified
          there.
        '';
      };
    };

    finalizer = mkOption {
      type = types.enum [
        "background"
        "foreground"
        "non-cascading"
      ];
      default = "non-cascading";
      description = ''
        Specify the default finalizer to apply to all ArgoCD application, by default.
      '';
    };

    kustomize.transformer = mkOption {
      type = with types; functionTo (listOf (attrsOf anything));
      default = res: res;
      defaultText = literalExpression "res: res";
      example = literalExpression ''
        map (lib.kube.removeLabels ["app.kubernetes.io/version"])
      '';
      description = ''
        Function that will be applied to the list of rendered manifests after kustomize rendering.
        This option applies to all kustomize applications in all nixidy applications unless
        explicitly specified there.
      '';
    };

    syncPolicy = {
      autoSync = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Specifies if applications should automatically sync.

            This is the default value for all applications if not explicitly set for the application.
          '';
        };
        prune = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Specifies if resources should be pruned during auto-syncing.

            This is the default value for all applications if not explicitly set for the application.
          '';
        };
        selfHeal = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Specifies if partial app sync should be executed when resources are changed only in
            target Kubernetes cluster and no git change detected.

            This is the default value for all applications if not explicitly set for the application.
          '';
        };
      };
    };

    destination = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The name of the cluster that ArgoCD should deploy all applications to.

          This is the default value for all applications if not explicitly set for the application.
        '';
      };
      server = mkOption {
        type = types.nullOr types.str;
        default = "https://kubernetes.default.svc";
        description = ''
          The Kubernetes server that ArgoCD should deploy all applications to.

          This is the default value for all applications if not explicitly set for the application.
        '';
      };
    };
  };
}
