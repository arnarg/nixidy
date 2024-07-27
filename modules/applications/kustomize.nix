{
  nixidyDefaults,
  lib,
  config,
  ...
}: let
  inherit (config) namespace;

  helpers = import ./lib.nix lib;
in {
  options = with lib; {
    kustomize.applications = mkOption {
      type = with types;
        attrsOf (submodule
          ({
            name,
            config,
            ...
          }: {
            options = {
              name = mkOption {
                type = types.str;
                default = name;
                description = "Name of the kustomize application.";
              };
              namespace = mkOption {
                type = types.str;
                default = namespace;
                defaultText = literalExpression "config.applications.<name>.namespace";
                description = "Namespace for the kustomize application.";
              };
              kustomization = {
                src = mkOption {
                  type = types.package;
                  description = "Derivation containing all the kustomize bases and overlays.";
                };
                path = mkOption {
                  type = types.str;
                  description = "Path relative to the base of `src` to the entrypoint kustomization directory.";
                };
              };
              transformer = mkOption {
                type = with types; functionTo (listOf (attrsOf anything));
                default = nixidyDefaults.kustomize.transformer;
                defaultText = literalExpression "config.nixidy.defaults.kustomize.transformer";
                description = ''
                  Function that will be applied to the list of rendered manifests from kustomize.
                '';
              };
              objects = mkOption {
                type = with types; listOf attrs;
                default = [];
                internal = true;
                description = "List of rendered kubernetes objects from helm chart.";
              };
            };

            config = {
              objects = with lib;
                pipe {
                  inherit (config) name namespace;
                  inherit (config.kustomization) src path;
                } [
                  kustomize.buildKustomization
                  builtins.readFile
                  kube.fromYAML
                  config.transformer
                ];
            };
          }));
      default = {};
      example = literalExpression ''
        {
          argocd = {
            namespace = "argocd";
            # Equivalent to `github.com/argoproj/argo-cd/manifests/cluster-install?ref=v2.9.3`
            # in kustomization.yaml.
            kustomization = {
              src = pkgs.fetchFromGitHub {
                owner = "argoproj";
                repo = "argo-cd";
                rev = "v2.9.3";
                hash = "sha256-GaY4Cw/LlSwy35umbB4epXt6ev8ya19UjHRwhDwilqU=";
              };
              path = "manifests/cluster-install";
            };
          };
        };
      '';
      description = ''
        Kustomize applications to render and add to the rendered application's resources.
      '';
    };
  };

  config = with lib; let
    groupedObjects = mapAttrs (_: release:
      {
        resources = [];
        objects = [];
      }
      // (groupBy (
          object: let
            gvk = helpers.getGVK object;
          in
            if config.types ? "${gvk.group}/${gvk.version}/${gvk.kind}"
            then "resources"
            else "objects"
        )
        release.objects))
    config.kustomize.applications;

    allResources = flatten (mapAttrsToList (_: groups: groups.resources) groupedObjects);
    allObjects = flatten (mapAttrsToList (_: groups: groups.objects) groupedObjects);
  in {
    resources = mkMerge (map (object: let
        gvk = helpers.getGVK object;
      in {
        ${gvk.group}.${gvk.version}.${gvk.kind}.${object.metadata.name} = object;
      })
      allResources);

    objects = allObjects;
  };
}
