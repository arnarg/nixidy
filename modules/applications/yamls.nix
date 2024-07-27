{
  lib,
  config,
  ...
}: let
  helpers = import ./lib.nix lib;
in {
  options = with lib; {
    yamls = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [
        ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: default
        ''
      ];
      description = ''
        List of Kubernetes manifests declared in YAML strings. They will be parsed and added to the application's
        `resources` where they can be overwritten and modified.

        Can be useful for reading existing YAML files (i.e. `[(builtins.readFile ./deployment.yaml)]`).
      '';
    };
  };

  config = with lib; let
    groupedObjects =
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
      ) (concatMap kube.fromYAML config.yamls));
  in {
    inherit (groupedObjects) objects;

    resources = mkMerge (map (object: let
        gvk = helpers.getGVK object;
      in {
        ${gvk.group}.${gvk.version}.${gvk.kind}.${object.metadata.name} = object;
      })
      groupedObjects.resources);
  };
}
