# Native module builder for CRDs.
#
# This is the value-producing counterpart to ./generator.nix. Where
# generator.nix renders the resource options to Nix *source text* and writes
# a `.nix` file (which then has to be `import`ed back — a serialize/deserialize
# round-trip plus an import-from-derivation), this builds the resource module
# as a Nix *value* directly: a `{ lib, options, config, ... }: { ... }` module
# that slots straight into `nixidy.applicationImports` (which already accepts
# `functionTo attrs`).
#
# The schema walk below is a faithful, value-emitting port of generator.nix's
# `genDefinitions`/`mapType`/`genResourceOptions`. The boilerplate that
# generator.nix inlines into every generated file's `let` block lives in
# ./runtime.nix and is imported here as real functions.
{
  name ? "crd",
  lib,
  schema,
  specialMapKeys ? { },
  skipCoerceToList ? { },
  definitionsOverlay ? f: p: p,
}:
let
  inherit (lib)
    head
    tail
    last
    sort
    elem
    any
    zipAttrs
    reverseList
    mapAttrs
    mapAttrsToList
    filterAttrs
    splitString
    ;

  applyOverlay =
    overlay: attr:
    let
      f = _final: attr;
    in
    lib.fix (lib.extends overlay f);

  # Overlaid schema definitions that the walk operates over. Type/alias
  # lookups (`hasTypeMapping`, alias following, self-reference checks) read
  # from this set — exactly as generator.nix's `genDefinitions` does.
  schemaDefs = applyOverlay definitionsOverlay schema.definitions;

  refDefinition = attr: head (tail (tail (splitString "/" attr."$ref")));

  hasTypeMapping =
    def:
    (def ? oneOf && any hasTypeMapping def.oneOf)
    || (
      def ? type
      && elem def.type [
        "string"
        "integer"
        "boolean"
        "number"
        "any"
      ]
    );

  # Pure resource-type bookkeeping (no module context needed).
  resourceTypes = schema.roots;

  compareVersions =
    ver1: ver2:
    let
      getVersion = lib.substring 1 10;
      splitVersion = v: builtins.splitVersion (getVersion v);
      isAlpha = v: elem "alpha" (splitVersion v);
      patchVersion =
        v:
        if isAlpha v then
          ""
        else if lib.length (splitVersion v) == 1 then
          "${getVersion v}prod"
        else
          getVersion v;
    in
    builtins.compareVersions (patchVersion ver1) (patchVersion ver2);

  resourceTypesByKind = zipAttrs (
    mapAttrsToList (_name: resourceType: {
      ${resourceType.kind} = resourceType;
    }) resourceTypes
  );

  resourcesTypesByKindSortByVersion = mapAttrs (
    _kind: rts: reverseList (sort (r1: r2: compareVersions r1.version r2.version > 0) rts)
  ) resourceTypesByKind;

  latestResourceTypesByKind = mapAttrs (_kind: last) resourcesTypesByKindSortByVersion;

  namespacedResourceTypes = filterAttrs (_: type: type.namespaced) resourceTypes;
in
# The resource module value.
{
  lib,
  options,
  config,
  ...
}:
with lib;
let
  # Runtime helpers, closed over the generated `definitions` (threaded back
  # lazily) and the module `config`.
  rt = import ./runtime.nix { inherit lib config definitions; };

  mapType =
    def:
    if def ? oneOf then
      rt.types.oneOf (map mapType (filter hasTypeMapping def.oneOf))
    else if def ? type then
      if def.type == "string" then
        if def ? format && def.format == "int-or-string" then
          rt.types.either rt.types.int rt.types.str
        else
          rt.types.str
      else if def.type == "integer" then
        rt.types.int
      else if def.type == "number" then
        rt.types.either rt.types.int rt.types.float
      else if def.type == "boolean" then
        rt.types.bool
      else if def.type == "object" then
        rt.types.attrs
      else if def.type == "array" then
        rt.types.listOf (mapType def.items)
      else if def.type == "any" then
        rt.types.unspecified
      else
        throw "type ${def.type} not supported"
    else
      throw "unknown definition";

  genResourceOptions =
    resource:
    mkOption {
      inherit (resource) description;
      type = rt.types.attrsOf (
        rt.submoduleForDefinition resource.ref resource.name resource.kind resource.group resource.version
      );
      default = { };
    };

  # The generated definition set: { <ref> = { options; config; }; }. Built
  # natively (real mkOption/types values), recursively referenced by the
  # runtime submodule helpers.
  definitions = mapAttrs (
    _name: definition:
    # an alias of another definition
    if definition ? "$ref" then
      schemaDefs.${refDefinition definition}
    else if !(definition ? properties) then
      { }
    else
      {
        options = mapAttrs (
          propName: property:
          let
            isRequired = elem propName (definition.required or [ ]);
            requiredOrNot = type: if isRequired then type else rt.types.nullOr type;
            optionProperties =
              if property ? "$ref" then
                # Our special "#/global" ref prefix gets typed metadata from the
                # shared (config-level) definition set. See crd2jsonschema.py.
                if hasPrefix "#/global" property."$ref" then
                  { type = requiredOrNot (rt.globalSubmoduleOf (refDefinition property)); }
                else if hasTypeMapping schemaDefs.${refDefinition property} then
                  { type = requiredOrNot (mapType schemaDefs.${refDefinition property}); }
                else
                  {
                    type =
                      if (refDefinition property) == _name then
                        rt.types.unspecified # do not allow self-referential values
                      else
                        requiredOrNot (rt.submoduleOf (refDefinition property));
                  }
              else if property.type == "array" then
                if property.items ? "$ref" then
                  if hasTypeMapping schemaDefs.${refDefinition property.items} then
                    { type = requiredOrNot (rt.types.listOf (mapType schemaDefs.${refDefinition property.items})); }
                  # attrset of submodules merged by x-kubernetes-patch-merge-key
                  else if
                    (property ? "x-kubernetes-patch-merge-key")
                    && (
                      !(property ? "x-kubernetes-list-map-keys")
                      || (property."x-kubernetes-list-map-keys" == [ property."x-kubernetes-patch-merge-key" ])
                    )
                  then
                    let
                      mergeKey = property."x-kubernetes-patch-merge-key";
                    in
                    {
                      type = requiredOrNot (
                        rt.coerceAttrsOfSubmodulesToListByKey (refDefinition property.items) mergeKey [ ]
                      );
                      apply = rt.attrsToList;
                    }
                  # attrset of submodules merged by "name"
                  else if
                    schemaDefs.${refDefinition property.items} ? properties
                    && schemaDefs.${refDefinition property.items}.properties ? name
                    && !(skipCoerceToList ? ${_name} && any (x: x == propName) skipCoerceToList.${_name})
                  then
                    {
                      type = requiredOrNot (
                        rt.coerceAttrsOfSubmodulesToListByKey (refDefinition property.items) "name" (
                          if specialMapKeys ? ${_name} && specialMapKeys.${_name} ? ${propName} then
                            specialMapKeys.${_name}.${propName}
                          else
                            property."x-kubernetes-list-map-keys" or [ ]
                        )
                      );
                      apply = rt.attrsToList;
                    }
                  else
                    {
                      type =
                        if (refDefinition property.items) == _name then
                          rt.types.unspecified # do not allow self-referential values
                        else
                          requiredOrNot (rt.types.listOf (rt.submoduleOf (refDefinition property.items)));
                    }
                else
                  { type = requiredOrNot (rt.types.listOf (mapType property.items)); }
              else if property.type == "object" && property ? additionalProperties then
                if
                  (
                    property.additionalProperties ? "$ref"
                    && hasTypeMapping schemaDefs.${refDefinition property.additionalProperties}
                  )
                then
                  {
                    type = requiredOrNot (
                      rt.types.attrsOf (mapType schemaDefs.${refDefinition property.additionalProperties})
                    );
                  }
                else if property.additionalProperties ? "$ref" then
                  { type = requiredOrNot rt.types.attrs; }
                else if property.additionalProperties.type == "array" then
                  { type = requiredOrNot (rt.types.loaOf (mapType property.additionalProperties.items)); }
                else
                  { type = requiredOrNot (rt.types.attrsOf (mapType property.additionalProperties)); }
              else
                { type = requiredOrNot (mapType property); };
          in
          mkOption (
            {
              description = property.description or "";
            }
            // optionProperties
          )
        ) definition.properties;

        config =
          let
            optionalProps = filterAttrs (
              propName: _property: !(elem propName (definition.required or [ ]))
            ) definition.properties;
          in
          mapAttrs (_name: _property: mkOverride 1002 null) optionalProps;
      }
  ) schemaDefs;

  # options.resources.<group>.<version>.<kind> plus the latest-version
  # <attrName> aliases.
  resourcesByGVK = foldl' recursiveUpdate { } (
    mapAttrsToList (
      _: rt: setAttrByPath [ rt.group rt.version rt.kind ] (genResourceOptions rt)
    ) resourceTypes
  );
  resourcesByAttrName = mapAttrs' (
    _: rt: nameValuePair rt.attrName (genResourceOptions rt)
  ) latestResourceTypesByKind;
in
{
  options.resources = resourcesByGVK // resourcesByAttrName;

  config = {
    # expose resource definitions
    inherit definitions;

    # register resource types
    types = mapAttrsToList (_: rt: {
      inherit (rt)
        name
        group
        version
        kind
        attrName
        ;
    }) resourceTypes;

    resources = foldl' recursiveUpdate { } (
      mapAttrsToList (
        _: rt:
        setAttrByPath [ rt.group rt.version rt.kind ] (mkAliasDefinitions options.resources.${rt.attrName})
      ) latestResourceTypesByKind
    );

    # make all namespaced resources default to the application's namespace
    defaults = mapAttrsToList (_: rt: {
      inherit (rt) group version kind;
      default.metadata.namespace = mkDefault config.namespace;
    }) namespacedResourceTypes;
  };
}
