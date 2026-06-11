lib: with lib; rec {
  getGVK =
    object:
    let
      splitApiVersion = splitString "/" object.apiVersion;
    in
    {
      inherit (object) kind;

      group = if length splitApiVersion < 2 then "core" else elemAt splitApiVersion 0;
      version = if length splitApiVersion < 2 then elemAt splitApiVersion 0 else elemAt splitApiVersion 1;
    };

  # Recursively flatten *List objects
  flattenListObjects = builtins.concatMap (
    object:
    if builtins.match "^.*List$" object.kind != null && builtins.isList (object.items or null) then
      flattenListObjects object.items
    else
      [ object ]
  );

  # Partition a flat list of kubernetes objects into typed `resources` and
  # untyped `objects`, based on whether each object's GVK is a registered type.
  #
  # `types` is the application's `config.types` registry (keyed
  # `<group>/<version>/<kind>`). Registered objects are returned as an
  # `mkMerge`-able attrset path (`<group>.<version>.<kind>.<name>`) so they flow
  # back into the typed `resources` option and can be patched; everything else
  # is returned as an opaque list. This is the single intake path shared by the
  # helm, kustomize and yamls modules.
  #
  # Type:
  #   partitionObjects :: AttrSet -> [AttrSet] -> { resources :: Merge; objects :: [AttrSet]; }
  partitionObjects =
    types: objects:
    let
      grouped = {
        resources = [ ];
        objects = [ ];
      }
      // builtins.groupBy (
        object:
        let
          gvk = getGVK object;
        in
        if types ? "${gvk.group}/${gvk.version}/${gvk.kind}" then "resources" else "objects"
      ) objects;
    in
    {
      resources = mkMerge (
        map (
          object:
          let
            gvk = getGVK object;
          in
          {
            ${gvk.group}.${gvk.version}.${gvk.kind}.${object.metadata.name} = object;
          }
        ) grouped.resources
      );

      inherit (grouped) objects;
    };

  # The filename stem for an object's rendered manifest: `<Kind>-<name>` with
  # dots in the name replaced by dashes. `build.nix` groups objects by this stem
  # (one YAML file per stem) and `yamls.nix` appends `.yaml` to detect collisions
  # with raw passthrough files; both MUST agree, so the policy lives here.
  #
  # Type:
  #   objectBaseName :: AttrSet -> String
  objectBaseName = object: "${object.kind}-${replaceStrings [ "." ] [ "-" ] object.metadata.name}";
}
