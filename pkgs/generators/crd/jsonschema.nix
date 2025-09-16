# This generator is based heavily on kubenix's generator.
# See: https://github.com/hall/kubenix/blob/main/pkgs/generators/k8s/default.nix
{
  name,
  pkgs,
  lib,
  spec,
}:
with lib;
let
  gen = rec {
    mkMerge = values: ''mkMerge [${concatMapStrings (value: "
      ${value}
    ") values}]'';

    toNixString =
      value:
      if isAttrs value || isList value then
        builtins.toJSON value
      else if isString value then
        ''"${value}"''
      else if value == null then
        "null"
      else
        builtins.toString value;

    removeEmptyLines =
      str:
      concatStringsSep "\n" (filter (l: builtins.match "[[:space:]]*" l != [ ]) (splitString "\n" str));

    mkOption =
      {
        description ? null,
        type ? null,
        default ? null,
        apply ? null,
      }:
      removeEmptyLines ''
        mkOption {
              ${optionalString (description != null) "description = ${builtins.toJSON description};"}
              ${optionalString (type != null) ''type = ${type};''}
              ${optionalString (default != null) ''default = ${toNixString default};''}
              ${optionalString (apply != null) ''apply = ${apply};''}
            }'';

    mkOverride = priority: value: "mkOverride ${toString priority} ${toNixString value}";

    types = {
      unspecified = "types.unspecified";
      str = "types.str";
      int = "types.int";
      float = "types.float";
      bool = "types.bool";
      attrs = "types.attrs";
      nullOr = val: "(types.nullOr ${val})";
      attrsOf = val: "(types.attrsOf ${val})";
      listOf = val: "(types.listOf ${val})";
      coercedTo =
        coercedType: coerceFunc: finalType:
        "(types.coercedTo ${coercedType} ${coerceFunc} ${finalType})";
      either = val1: val2: "(types.either ${val1} ${val2})";
      loaOf = type: "(types.loaOf ${type})";

      mapNumType =
        base: def:
        let
          # Handle minimum value constraints from JSON Schema
          # JSON Schema supports both regular minimum and exclusiveMinimum:
          # - exclusiveMinimum: true means value must be > minimum (not >=)
          # - exclusiveMinimum: <integer> means value must be >= that integer (exclusive constraint)
          min =
            # If exclusiveMinimum is defined
            if def ? exclusiveMinimum then
              # If it's a boolean true, we make the minimum exclusive by incrementing it
              if lib.isBool def.exclusiveMinimum then
                # If minimum is also defined, increment it to make it exclusive
                if def ? minimum then def.minimum + 1 else null
              # If it's an integer, use that as the exclusive minimum directly
              else if lib.isInt def.exclusiveMinimum then
                def.exclusiveMinimum
              # Otherwise, no minimum constraint
              else
                null
            # If no exclusiveMinimum but regular minimum is defined, use it as-is
            else if def ? minimum then
              def.minimum
            # No minimum constraint
            else
              null;

          # Handle maximum value constraints from JSON Schema
          # Similar logic to minimum but for maximum values:
          # - exclusiveMaximum: true means value must be < maximum (not <=)
          # - exclusiveMaximum: <integer> means value must be <= that integer (exclusive constraint)
          max =
            # If exclusiveMaximum is defined
            if def ? exclusiveMaximum then
              # If it's a boolean true, we make the maximum exclusive by decrementing it
              if lib.isBool def.exclusiveMaximum then
                # If maximum is also defined, decrement it to make it exclusive
                if def ? maximum then def.maximum - 1 else null
              # If it's an integer, use that as the exclusive maximum directly
              else if lib.isInt def.exclusiveMaximum then
                def.exclusiveMaximum
              # Otherwise, no maximum constraint
              else
                null
            # If no exclusiveMaximum but regular maximum is defined, use it as-is
            else if def ? maximum then
              def.maximum
            # No maximum constraint
            else
              null;

          # Collect validators that should be added
          validators =
            if def != null then
              lib.remove null [
                (if min != null then "(types.minimumNum ${toString min})" else null)
                (if max != null then "(types.maximumNum ${toString max})" else null)
                (if def ? "multipleOf" then "(types.multipleOfNum ${toString def.multipleOf})" else null)
              ]
            else
              [ ];
        in
        if lib.length validators > 0 then
          "(types.mergeValidators ${base} [${lib.concatStringsSep " " validators}])"
        else
          base;
    };

    hasTypeMapping =
      def:
      hasAttr "type" def
      && elem def.type [
        "string"
        "integer"
        "boolean"
      ];

    mergeValuesByKey = mergeKey: ''(mergeValuesByKey "${mergeKey}")'';

    mapType =
      def:
      if def.type == "string" then
        if hasAttr "format" def && def.format == "int-or-string" then
          types.either types.int types.str
        else
          types.str
      else if def.type == "integer" then
        types.mapNumType types.int def
      else if def.type == "number" then
        types.either (types.mapNumType types.int def) (types.mapNumType types.float def)
      else if def.type == "boolean" then
        types.bool
      else if def.type == "object" then
        types.attrs
      else
        throw "type ${def.type} not supported";

    submoduleOf = _definitions: ref: ''(submoduleOf "${ref}")'';

    globalSubmoduleOf = _def: ref: ''(globalSubmoduleOf "${ref}")'';

    submoduleForDefinition =
      ref: name: kind: group: version:
      ''(submoduleForDefinition "${ref}" "${name}" "${kind}" "${group}" "${version}")'';

    coerceAttrsOfSubmodulesToListByKey =
      ref: attrMergeKey: listMergeKeys:
      ''(coerceAttrsOfSubmodulesToListByKey "${ref}" "${attrMergeKey}" [${
        concatStringsSep " " (map (key: "\"${toString key}\"") listMergeKeys)
      }])'';

    attrsToList = "attrsToList";

    refDefinition = attr: head (tail (tail (splitString "/" attr."$ref")));
  };

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

      v1 = patchVersion ver1;
      v2 = patchVersion ver2;
    in
    builtins.compareVersions v1 v2;

  fixJSON = replaceStrings [ "\\u" ] [ "u" ];

  fetchSpecs = path: builtins.fromJSON (fixJSON (builtins.readFile path));

  genDefinitions =
    schema:
    with gen;
    mapAttrs (
      _name: definition:
      # if $ref is in definition it means it's an alias of other definition
      if hasAttr "$ref" definition then
        definitions."${refDefinition definition}"
      else if !(hasAttr "properties" definition) then
        { }
      # in other case it's an actual definition
      else
        {
          options = mapAttrs (
            propName: property:
            let
              isRequired = elem propName (definition.required or [ ]);
              requiredOrNot = type: if isRequired then type else types.nullOr type;
              optionProperties =
                # if $ref is in property it references other definition,
                # but if other definition does not have properties, then just take it's type
                if hasAttr "$ref" property then
                  # Handle our special "#/global" ref prefix, used exclusively to get typed
                  # metadata from CRDs.
                  # See: crd2jsonschema.py
                  if hasPrefix "#/global" property."$ref" then
                    {
                      type = requiredOrNot (globalSubmoduleOf definitions (refDefinition property));
                    }
                  else if hasTypeMapping schema.definitions.${refDefinition property} then
                    {
                      type = requiredOrNot (mapType schema.definitions.${refDefinition property});
                    }
                  else
                    {
                      type =
                        if (refDefinition property) == _name then
                          types.unspecified # do not allow self-referential values
                        else
                          requiredOrNot (submoduleOf definitions (refDefinition property));
                    }
                # if property has an array type
                else if property.type == "array" then
                  # if reference is in items it can reference other type of another
                  # definition
                  if hasAttr "$ref" property.items then
                    # if it is a reference to simple type
                    if hasTypeMapping schema.definitions.${refDefinition property.items} then
                      {
                        type = requiredOrNot (
                          types.listOf (mapType schema.definitions.${refDefinition property.items}.type)
                        );
                      }
                    # if a reference is to complex type
                    else
                    # make it an attribute set of submodules if only x-kubernetes-patch-merge-key is present, or
                    # x-kubernetes-patch-merge-key == x-kubernetes-list-map-keys.
                    if
                      (hasAttr "x-kubernetes-patch-merge-key" property)
                      && (
                        !(hasAttr "x-kubernetes-list-map-keys" property)
                        || (property."x-kubernetes-list-map-keys" == [ property."x-kubernetes-patch-merge-key" ])
                      )
                    then
                      let
                        mergeKey = property."x-kubernetes-patch-merge-key";
                      in
                      {
                        type = requiredOrNot (
                          coerceAttrsOfSubmodulesToListByKey (refDefinition property.items) mergeKey [ ]
                        );
                        apply = attrsToList;
                      }
                    # in other case it's a simple list
                    else
                    # make it an attribute set of submodules if only x-kubernetes-patch-merge-key is present, or
                    # x-kubernetes-patch-merge-key == x-kubernetes-list-map-keys.
                    if
                      hasAttr "properties" schema.definitions.${refDefinition property.items}
                      && hasAttr "name" schema.definitions.${refDefinition property.items}.properties
                    then
                      let
                        mergeKey = "name";
                      in
                      {
                        type = requiredOrNot (
                          coerceAttrsOfSubmodulesToListByKey (refDefinition property.items) mergeKey (
                            if hasAttr "x-kubernetes-list-map-keys" property then property."x-kubernetes-list-map-keys" else [ ]
                          )
                        );
                        apply = attrsToList;
                      }
                    else
                      {
                        type =
                          if (refDefinition property.items) == _name then
                            types.unspecified # do not allow self-referential values
                          else
                            requiredOrNot (types.listOf (submoduleOf definitions (refDefinition property.items)));
                      }
                  # in other case it only references a simple type
                  else
                    {
                      type = requiredOrNot (types.listOf (mapType property.items));
                    }
                else if property.type == "object" && hasAttr "additionalProperties" property then
                  # if it is a reference to simple type
                  if
                    (
                      hasAttr "$ref" property.additionalProperties
                      && hasTypeMapping schema.definitions.${refDefinition property.additionalProperties}
                    )
                  then
                    {
                      type = requiredOrNot (
                        types.attrsOf (mapType schema.definitions.${refDefinition property.additionalProperties})
                      );
                    }
                  else if hasAttr "$ref" property.additionalProperties then
                    {
                      type = requiredOrNot types.attrs;
                    }
                  # if is an array
                  else if property.additionalProperties.type == "array" then
                    {
                      type = requiredOrNot (types.loaOf (mapType property.additionalProperties.items));
                    }
                  else
                    {
                      type = requiredOrNot (types.attrsOf (mapType property.additionalProperties));
                    }
                # just a simple property
                else
                  {
                    type = requiredOrNot (mapType property);
                  };
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
    ) schema.definitions;

  genResourceTypes =
    schema:
    lib.attrsets.mergeAttrsList (
      map (root: {
        "${root.ref}" = root;
      }) schema.roots
    );

  schema = fetchSpecs spec;
  definitions = genDefinitions schema;
  resourceTypes = genResourceTypes schema;

  resourceTypesByKind = zipAttrs (
    mapAttrsToList (_name: resourceType: {
      ${resourceType.kind} = resourceType;
    }) resourceTypes
  );

  resourcesTypesByKindSortByVersion = mapAttrs (
    _kind: resourceTypes:
    reverseList (sort (r1: r2: compareVersions r1.version r2.version > 0) resourceTypes)
  ) resourceTypesByKind;

  latestResourceTypesByKind = mapAttrs (_kind: last) resourcesTypesByKindSortByVersion;

  namespacedResourceTypes = filterAttrs (_: type: type.namespaced) resourceTypes;

  genResourceOptions =
    resource:
    with gen;
    let
      submoduleForDefinition' =
        definition:
        submoduleForDefinition definition.ref definition.name definition.kind definition.group
          definition.version;
    in
    mkOption {
      inherit (resource) description;
      type = types.attrsOf (submoduleForDefinition' resource);
      default = { };
    };

  generated = ''
    # This file was generated with nixidy CRD generator, do not edit.
    { lib, options, config, ... }:

    with lib;

    let
      hasAttrNotNull = attr: set: hasAttr attr set && set.''${attr} != null;

      attrsToList = values:
        if values != null
        then
          sort (a: b:
            if (hasAttrNotNull "_priority" a && hasAttrNotNull "_priority" b)
            then a._priority < b._priority
            else false
          ) (mapAttrsToList (n: v: v) values)
        else
          values;

      getDefaults = resource: group: version: kind:
        catAttrs "default" (filter (default:
          (default.resource == null || default.resource == resource) &&
          (default.group == null || default.group == group) &&
          (default.version == null || default.version == version) &&
          (default.kind == null || default.kind == kind)
        ) config.defaults);

      types = lib.types // rec {
        str = mkOptionType {
          name = "str";
          description = "string";
          check = isString;
          merge = mergeEqualOption;
        };

        minimumNum = min: base: lib.types.addCheck base (x: x >= min) // {
          name = "minimumNum";
          description = "''${base.description}, higher than ''${toString min}";
          descriptionClass = "noun";
        };

        maximumNum = max: base: lib.types.addCheck base (x: x <= max) // {
          name = "maximumNum";
          description = "''${base.description}, lower than ''${toString max}";
          descriptionClass = "noun";
        };

        multipleOfNum = mult: base: lib.types.addCheck base (x: lib.mod x mult == 0) // {
          name = "multipleOfNum";
          description = "''${base.description}, multiple of ''${toString mult}";
          descriptionClass = "noun";
        };

        mergeValidators = base: vals: lib.foldl (a: b: b a) base vals;

        # Either value of type `finalType` or `coercedType`, the latter is
        # converted to `finalType` using `coerceFunc`.
        coercedTo = coercedType: coerceFunc: finalType:
        mkOptionType rec {
          inherit (finalType) getSubOptions getSubModules;

          name = "coercedTo";
          description = "''${finalType.description} or ''${coercedType.description}";
          check = x: finalType.check x || coercedType.check x;
          merge = loc: defs:
            let
              coerceVal = val:
                if finalType.check val then val
                else let
                  coerced = coerceFunc val;
                in assert finalType.check coerced; coerced;

            in finalType.merge loc (map (def: def // { value = coerceVal def.value; }) defs);
          substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
          typeMerge = t1: t2: null;
          functor = (defaultFunctor name) // { wrapped = finalType; };
        };
      };

      mkOptionDefault = mkOverride 1001;

      mergeValuesByKey = attrMergeKey: listMergeKeys: values:
        listToAttrs (imap0
          (i: value: nameValuePair (
            if hasAttr attrMergeKey value
            then
              if isAttrs value.''${attrMergeKey}
              then toString value.''${attrMergeKey}.content
              else (toString value.''${attrMergeKey})
            else
              # generate merge key for list elements if it's not present
              "__kubenix_list_merge_key_" + (concatStringsSep "" (map (key:
                if isAttrs value.''${key}
                then toString value.''${key}.content
                else (toString value.''${key})
              ) listMergeKeys))
          ) (value // { _priority = i; }))
        values);

      submoduleOf = ref: types.submodule ({name, ...}: {
        options = definitions."''${ref}".options or {};
        config = definitions."''${ref}".config or {};
      });

      globalSubmoduleOf = ref: types.submodule ({name, ...}: {
        options = config.definitions."''${ref}".options or {};
        config = config.definitions."''${ref}".config or {};
      });

      submoduleWithMergeOf = ref: mergeKey: types.submodule ({name, ...}: let
        convertName = name:
          if definitions."''${ref}".options.''${mergeKey}.type == types.int
          then toInt name
          else name;
      in {
        options = definitions."''${ref}".options // {
          # position in original array
          _priority = mkOption { type = types.nullOr types.int; default = null; };
        };
        config = definitions."''${ref}".config // {
          ''${mergeKey} = mkOverride 1002 (
            # use name as mergeKey only if it is not coming from mergeValuesByKey
            if (!hasPrefix "__kubenix_list_merge_key_" name)
            then convertName name
            else null
          );
        };
      });

      submoduleForDefinition = ref: resource: kind: group: version: let
        apiVersion = if group == "core" then version else "''${group}/''${version}";
      in types.submodule ({name, ...}: {
        inherit (definitions."''${ref}") options;

        imports = getDefaults resource group version kind;
        config = mkMerge [
          definitions."''${ref}".config
          {
            kind = mkOptionDefault kind;
            apiVersion = mkOptionDefault apiVersion;

            # metdata.name cannot use option default, due deep config
            metadata.name = mkOptionDefault name;
          }
        ];
      });

      coerceAttrsOfSubmodulesToListByKey = ref: attrMergeKey: listMergeKeys: (types.coercedTo
        (types.listOf (submoduleOf ref))
        (mergeValuesByKey attrMergeKey listMergeKeys)
        (types.attrsOf (submoduleWithMergeOf ref attrMergeKey))
      );

      definitions = {
        ${concatStrings (
          mapAttrsToList (name: value: ''
            "${name}" = {
              ${optionalString (hasAttr "options" value) "
            options = {${
                            concatStrings (
                              mapAttrsToList (name: value: ''
                                "${name}" = ${value};
                              '') value.options
                            )
                          }};
            "}

              ${optionalString (hasAttr "config" value) ''
                config = {${
                  concatStrings (
                    mapAttrsToList (name: value: ''
                      "${name}" = ${value};
                    '') value.config
                  )
                }};
              ''}
            };
          '') definitions
        )}
      };
    in {
      # all resource versions
      options = {
        resources = {
          ${concatStrings (
            mapAttrsToList (_: rt: ''
              "${rt.group}"."${rt.version}"."${rt.kind}" = ${genResourceOptions rt};
            '') resourceTypes
          )}
        } // {
          ${concatStrings (
            mapAttrsToList (_: rt: ''
              "${rt.attrName}" = ${genResourceOptions rt};
            '') latestResourceTypesByKind
          )}
        };
      };

      config = {
        # expose resource definitions
        inherit definitions;

        # register resource types
        types = [${
          concatStrings (
            mapAttrsToList (_: rt: ''
              {
                        name = "${rt.name}";
                        group = "${rt.group}";
                        version = "${rt.version}";
                        kind = "${rt.kind}";
                        attrName = "${rt.attrName}";
                      }'') resourceTypes
          )
        }];

        resources = {
          ${concatStrings (
            mapAttrsToList (_: rt: ''
              "${rt.group}"."${rt.version}"."${rt.kind}" =
                mkAliasDefinitions options.resources."${rt.attrName}";
            '') latestResourceTypesByKind
          )}
        };

        # make all namespaced resources default to the
        # application's namespace
        defaults = [${
          concatStrings (
            mapAttrsToList (_: rt: ''
              {
                  group = "${rt.group}";
                  version = "${rt.version}";
                  kind = "${rt.kind}";
                  default.metadata.namespace = lib.mkDefault config.namespace;
                }'') namespacedResourceTypes
          )
        }];
      };
    }
  '';
in
pkgs.runCommand "k8s-${name}-gen.nix"
  {
    buildInputs = [ pkgs.nixfmt-rfc-style ];
  }
  ''
    cat << 'GENERATED' > ./raw.nix
    ${generated}
    GENERATED

    nixfmt ./raw.nix
    cp ./raw.nix $out
  ''
