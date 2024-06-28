{
  lib,
  config,
  ...
}: let
  cfg = config.nixidy;

  apps = builtins.removeAttrs config.applications [cfg.appOfApps.name];

  extraFilesOpts = with lib;
    {name, ...}: {
      options = {
        path = mkOption {
          type = types.str;
          default = name;
          description = "Path of output file.";
        };
        text = mkOption {
          type = types.lines;
          description = "Text of the output file.";
        };
      };
    };

  walkDir = prefix: dir: let
    contents = builtins.readDir "${prefix}/${dir}";
  in
    if contents ? "default.nix" && contents."default.nix" == "regular"
    then lib.helm.downloadHelmChart (import "${prefix}/${dir}")
    else
      builtins.listToAttrs (map (
        d: {
          name = d.name;
          value = walkDir "${prefix}/${dir}" d.name;
        }
      ) (lib.filter (c: c.value == "directory") (lib.attrsToList contents)));

  mkChartAttrs = dir: let
    contents = builtins.readDir dir;
  in
    builtins.listToAttrs (map (
      d: {
        name = d.name;
        value = walkDir dir d.name;
      }
    ) (lib.filter (c: c.value == "directory") (lib.attrsToList contents)));
in {
  options.nixidy = with lib; {
    target = {
      repository = mkOption {
        type = types.str;
        description = "The repository URL to put in all generated applications.";
      };
      branch = mkOption {
        type = types.str;
        description = "The destination branch of the generated applications.";
      };
      rootPath = mkOption {
        type = types.str;
        default = "./";
        description = "The root path of all generated applications in the repository.";
      };
    };

    extraFiles = mkOption {
      type = types.attrsOf (types.submodule extraFilesOpts);
      default = {};
      description = ''
        Extra files to write in the generated stage.
      '';
    };

    defaults = {
      helm.transformer = mkOption {
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
        automated = {
          prune = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if resources should be pruned during auto-syncing.
              This is the default value for all applications if not explicitly set.
            '';
          };
          selfHeal = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if partial app sync should be executed when resources are changed only in
              target Kubernetes cluster and no git change detected.
              This is the default value for all applications if not explicitly set.
            '';
          };
        };
      };
    };

    appOfApps = {
      name = mkOption {
        type = types.str;
        default = "apps";
        description = "Name of the application for bootstrapping all other applications (app of apps pattern).";
      };
      namespace = mkOption {
        type = types.str;
        default = "argocd";
        description = "Destination namespace for generated Argo CD Applications in the app of apps applications.";
      };
    };

    charts = mkOption {
      type = with types; attrsOf anything;
      default = {};
      description = "Attrset of derivations containing helm charts. This will be passed as `charts` to every module.";
    };
    chartsDir = mkOption {
      type = with types; nullOr path;
      default = null;
      description = "Path to a directory containing sub-directory structure that can be used to build a charts attrset. This will be passed as `charts` to every module.";
    };
  };

  config = {
    applications.${cfg.appOfApps.name} = {
      namespace = cfg.appOfApps.namespace;

      resources.applications =
        lib.attrsets.mapAttrs (
          n: app: {
            metadata.name = n;
            spec = {
              project = app.project;
              source = {
                repoURL = cfg.target.repository;
                targetRevision = cfg.target.branch;
                path = lib.path.subpath.join [
                  cfg.target.rootPath
                  app.output.path
                ];
              };
              destination = {
                server = "https://kubernetes.default.svc";
                namespace = app.namespace;
              };
              syncPolicy.automated = {
                prune = app.syncPolicy.automated.prune;
                selfHeal = app.syncPolicy.automated.selfHeal;
              };
            };
          }
        )
        apps;
    };

    _module.args.charts = config.nixidy.charts;
    nixidy.charts = lib.optionalAttrs (cfg.chartsDir != null) (mkChartAttrs cfg.chartsDir);
  };
}
