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
    helm.releases = mkOption {
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
                description = "Name of the helm release.";
              };
              namespace = mkOption {
                type = types.str;
                default = namespace;
                defaultText = literalExpression "config.applications.<name>.namespace";
                description = "Namespace for the release.";
              };
              chart = mkOption {
                type = types.package;
                description = ''
                  Derivation containing the helm chart for the release.
                '';
              };
              values = mkOption {
                type = types.attrsOf types.anything;
                default = {};
                description = ''
                  Values to pass to the helm chart when rendering it.
                '';
              };
              includeCRDs = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Whether or not to include CRDs in the helm release.
                '';
              };
              transformer = mkOption {
                type = with types; functionTo (listOf (attrsOf anything));
                default = nixidyDefaults.helm.transformer;
                defaultText = literalExpression "config.nixidy.defaults.helm.transformer";
                example = literalExpression ''
                  map (lib.kube.removeLabels ["helm.sh/chart"])
                '';
                description = ''
                  Function that will be applied to the list of rendered manifests after the helm templating.
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
                pipe {inherit (config) name namespace chart values includeCRDs;} [
                  helm.buildHelmChart
                  builtins.readFile
                  kube.fromYAML
                  config.transformer
                ];
            };
          }));
      default = {};
      description = ''
        Helm releases to template and add to the rendered application's resources.
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
    config.helm.releases;

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
