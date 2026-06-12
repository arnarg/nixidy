# Backend-agnostic CRD schema walk.
#
# Turns a crd2jsonschema schema into the structured pieces both generator
# backends need: the per-definition option set, the resource roots, and the
# version/kind bookkeeping. Every option and type is constructed through the
# supplied `backend` (`b`), so the SAME walk drives both:
#   - the text backend (./backend-text.nix) → Nix source, assembled by
#     ./generator.nix into a committable `.nix` file, and
#   - the value backend (./backend-value.nix) → live module values, assembled
#     by ./module.nix into a `{ lib, options, config, ... }: { ... }` module.
#
# Keeping this walk single-sourced is the point: the type/coercion branch logic
# (the part most likely to drift) lives in exactly one place.
{ lib }:
with lib;
let
  applyOverlay =
    overlay: attr:
    let
      f = _final: attr;
    in
    fix (extends overlay f);

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

  compareVersions =
    ver1: ver2:
    let
      getVersion = substring 1 10;
      splitVersion = v: builtins.splitVersion (getVersion v);
      isAlpha = v: elem "alpha" (splitVersion v);
      patchVersion =
        v:
        if isAlpha v then
          ""
        else if length (splitVersion v) == 1 then
          "${getVersion v}prod"
        else
          getVersion v;
    in
    builtins.compareVersions (patchVersion ver1) (patchVersion ver2);
in
{
  walk =
    b:
    {
      schema,
      skipCoerceToList ? { },
      specialMapKeys ? { },
      definitionsOverlay ? f: p: p,
    }:
    let
      schemaDefs = applyOverlay definitionsOverlay schema.definitions;
      resourceTypes = schema.roots;

      resourceTypesByKind = zipAttrs (
        mapAttrsToList (_name: rt: {
          ${rt.kind} = rt;
        }) resourceTypes
      );
      resourcesTypesByKindSortByVersion = mapAttrs (
        _kind: rts: reverseList (sort (r1: r2: compareVersions r1.version r2.version > 0) rts)
      ) resourceTypesByKind;
      latestResourceTypesByKind = mapAttrs (_kind: last) resourcesTypesByKindSortByVersion;
      namespacedResourceTypes = filterAttrs (_: type: type.namespaced) resourceTypes;

      mapType =
        def:
        if def ? oneOf then
          b.types.oneOf (map mapType (filter hasTypeMapping def.oneOf))
        else if def ? type then
          if def.type == "string" then
            if def ? format && def.format == "int-or-string" then
              b.types.either b.types.int b.types.str
            else
              b.types.str
          else if def.type == "integer" then
            b.types.int
          else if def.type == "number" then
            b.types.either b.types.int b.types.float
          else if def.type == "boolean" then
            b.types.bool
          else if def.type == "object" then
            b.types.attrs
          else if def.type == "array" then
            b.types.listOf (mapType def.items)
          else if def.type == "any" then
            b.types.unspecified
          else
            throw "type ${def.type} not supported"
        else
          throw "unknown definition";

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
                requiredOrNot = type: if isRequired then type else b.types.nullOr type;
                optionProperties =
                  if property ? "$ref" then
                    # Our special "#/global" ref prefix gets typed metadata from
                    # the shared (config-level) definition set. See crd2jsonschema.py.
                    if hasPrefix "#/global" property."$ref" then
                      { type = requiredOrNot (b.globalSubmoduleOf (refDefinition property)); }
                    else if hasTypeMapping schemaDefs.${refDefinition property} then
                      { type = requiredOrNot (mapType schemaDefs.${refDefinition property}); }
                    else
                      {
                        type =
                          if (refDefinition property) == _name then
                            b.types.unspecified # do not allow self-referential values
                          else
                            requiredOrNot (b.submoduleOf (refDefinition property));
                      }
                  else if property.type == "array" then
                    if property.items ? "$ref" then
                      if hasTypeMapping schemaDefs.${refDefinition property.items} then
                        { type = requiredOrNot (b.types.listOf (mapType schemaDefs.${refDefinition property.items})); }
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
                            b.coerceAttrsOfSubmodulesToListByKey (refDefinition property.items) mergeKey [ ]
                          );
                          apply = b.attrsToList;
                        }
                      # attrset of submodules merged by "name"
                      else if
                        schemaDefs.${refDefinition property.items} ? properties
                        && schemaDefs.${refDefinition property.items}.properties ? name
                        && !(skipCoerceToList ? ${_name} && any (x: x == propName) skipCoerceToList.${_name})
                      then
                        {
                          type = requiredOrNot (
                            b.coerceAttrsOfSubmodulesToListByKey (refDefinition property.items) "name" (
                              if specialMapKeys ? ${_name} && specialMapKeys.${_name} ? ${propName} then
                                specialMapKeys.${_name}.${propName}
                              else
                                property."x-kubernetes-list-map-keys" or [ ]
                            )
                          );
                          apply = b.attrsToList;
                        }
                      else
                        {
                          type =
                            if (refDefinition property.items) == _name then
                              b.types.unspecified # do not allow self-referential values
                            else
                              requiredOrNot (b.types.listOf (b.submoduleOf (refDefinition property.items)));
                        }
                    else
                      { type = requiredOrNot (b.types.listOf (mapType property.items)); }
                  else if property.type == "object" && property ? additionalProperties then
                    if
                      (
                        property.additionalProperties ? "$ref"
                        && hasTypeMapping schemaDefs.${refDefinition property.additionalProperties}
                      )
                    then
                      {
                        type = requiredOrNot (
                          b.types.attrsOf (mapType schemaDefs.${refDefinition property.additionalProperties})
                        );
                      }
                    else if property.additionalProperties ? "$ref" then
                      { type = requiredOrNot b.types.attrs; }
                    else if property.additionalProperties.type == "array" then
                      { type = requiredOrNot (b.types.loaOf (mapType property.additionalProperties.items)); }
                    else
                      { type = requiredOrNot (b.types.attrsOf (mapType property.additionalProperties)); }
                  else
                    { type = requiredOrNot (mapType property); };
              in
              b.mkOption (
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
              mapAttrs (_name: _property: b.mkOverrideNull) optionalProps;
          }
      ) schemaDefs;

      genResourceOptions =
        resource:
        b.mkOption {
          inherit (resource) description;
          type = b.types.attrsOf (
            b.submoduleForDefinition resource.ref resource.name resource.kind resource.group resource.version
          );
          default = { };
        };
    in
    {
      inherit
        definitions
        resourceTypes
        latestResourceTypesByKind
        namespacedResourceTypes
        genResourceOptions
        ;
    };
}
