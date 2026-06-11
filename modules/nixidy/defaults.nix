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
  };
}
