# Native module builder for CRDs.
#
# Value-backend assembler: drives the shared schema walk (./walk.nix) with the
# value backend (./backend-value.nix) to produce the resource definitions as a
# Nix *value* — a `{ lib, options, config, ... }: { ... }` module — instead of
# the source file ./generator.nix builds. The result slots straight into
# `nixidy.applicationImports` (which already accepts `functionTo attrs`), so
# there is no generated file and no import-from-derivation: only the Python
# crd2jsonschema parse remains (shared via `sources/crd.nix`'s `crdSchema`).
{
  name ? "crd",
  lib,
  schema,
  specialMapKeys ? { },
  skipCoerceToList ? { },
  definitionsOverlay ? f: p: p,
}:
# The resource module value.
{
  lib,
  options,
  config,
  ...
}:
with lib;
let
  # Shared walk, driven by the value backend. `rt` (the runtime helpers) closes
  # over the generated `definitions`, which is itself produced by the walk —
  # the mutual recursion is lazy-safe (submodule bodies force `definitions`
  # only when an option is evaluated).
  parts = (import ./walk.nix { inherit lib; }).walk b {
    inherit
      schema
      specialMapKeys
      skipCoerceToList
      definitionsOverlay
      ;
  };
  inherit (parts)
    definitions
    resourceTypes
    latestResourceTypesByKind
    namespacedResourceTypes
    genResourceOptions
    ;

  rt = import ./runtime.nix { inherit lib config definitions; };
  b = import ./backend-value.nix { inherit lib rt; };
in
{
  # options.resources.<group>.<version>.<kind> plus the latest-version
  # <attrName> aliases.
  options.resources =
    (foldl' recursiveUpdate { } (
      mapAttrsToList (
        _: r: setAttrByPath [ r.group r.version r.kind ] (genResourceOptions r)
      ) resourceTypes
    ))
    // (mapAttrs' (_: r: nameValuePair r.attrName (genResourceOptions r)) latestResourceTypesByKind);

  config = {
    # expose resource definitions
    inherit definitions;

    # register resource types
    types = mapAttrsToList (_: r: {
      inherit (r)
        name
        group
        version
        kind
        attrName
        ;
    }) resourceTypes;

    resources = foldl' recursiveUpdate { } (
      mapAttrsToList (
        _: r:
        setAttrByPath [ r.group r.version r.kind ] (mkAliasDefinitions options.resources.${r.attrName})
      ) latestResourceTypesByKind
    );

    # make all namespaced resources default to the application's namespace
    defaults = mapAttrsToList (_: r: {
      inherit (r) group version kind;
      default.metadata.namespace = mkDefault config.namespace;
    }) namespacedResourceTypes;
  };
}
