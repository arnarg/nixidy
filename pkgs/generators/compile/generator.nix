# This generator is based heavily on kubenix's generator.
# See: https://github.com/hall/kubenix/blob/main/pkgs/generators/k8s/default.nix
#
# Text backend assembler: drives the shared schema walk (./walk.nix) with the
# text backend (./backend-text.nix) to render Nix source, then writes a
# standalone, committable `.nix` module file. The runtime helpers the generated
# file relies on are inlined into its `let` block below; ./runtime.nix is the
# value-form twin of those helpers used by the native module generator.
{
  name,
  pkgs,
  lib,
  schema,
  specialMapKeys ? { },
  skipCoerceToList ? { },
  definitionsOverlay ? f: p: p,
}:
with lib;
let
  parts = (import ./walk.nix { inherit lib; }).walk (import ./backend-text.nix { inherit lib; }) {
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

  generated = ''
    # This file was generated with nixidy resource generator, do not edit.
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

        # Numeric bounds.
        withMinimum =
          min: base:
          lib.types.addCheck base (x: x >= min)
          // {
            description = "''${base.description} (minimum ''${toString min})";
          };
        withMaximum =
          max: base:
          lib.types.addCheck base (x: x <= max)
          // {
            description = "''${base.description} (maximum ''${toString max})";
          };
        withExclusiveMinimum =
          min: base:
          lib.types.addCheck base (x: x > min)
          // {
            description = "''${base.description} (exclusive minimum ''${toString min})";
          };
        withExclusiveMaximum =
          max: base:
          lib.types.addCheck base (x: x < max)
          // {
            description = "''${base.description} (exclusive maximum ''${toString max})";
          };
        withMultipleOf =
          m: base:
          lib.types.addCheck base (x: mod x m == 0)
          // {
            description = "''${base.description} (multiple of ''${toString m})";
          };

        # String constraints.
        withMinLength =
          n: base:
          lib.types.addCheck base (x: stringLength x >= n)
          // {
            description = "''${base.description} (min length ''${toString n})";
          };
        withMaxLength =
          n: base:
          lib.types.addCheck base (x: stringLength x <= n)
          // {
            description = "''${base.description} (max length ''${toString n})";
          };
        withPattern =
          p: base:
          # builtins.match compiles POSIX ERE, but JSON Schema patterns are
          # ECMAScript, and an unsupported construct makes it throw an uncatchable
          # error at compile time (tryEval won't rescue it), aborting evaluation.
          # Since the throw can't be caught we decide statically and conservatively:
          # translate the class escapes POSIX lacks (`\d`, `\s`, `\w`, negations,
          # and `\/`) for the simple case, then apply the check ONLY for patterns we
          # can be sure compile, skipping otherwise. The API server validates the
          # real pattern regardless. Skip when the original pattern contains a
          # character class `[…]` (POSIX bracket sub-syntax diverges from ECMAScript
          # and replaceStrings translation is context-blind inside a class), a brace
          # `{` (interval divergence), a `(?…)` group, or an unsupported escape (one
          # that survives peeling off every escape POSIX accepts). Validates only the
          # class-free subset, but never crashes and never mis-validates.
          let
            posixPattern = builtins.replaceStrings
              [ "\\d" "\\D" "\\s" "\\S" "\\w" "\\W" "\\/" ]
              [ "[0-9]" "[^0-9]" "[[:space:]]" "[^[:space:]]" "[0-9A-Za-z_]" "[^0-9A-Za-z_]" "/" ]
              p;
            peeled = builtins.replaceStrings
              [ "\\\\" "\\." "\\(" "\\)" "\\[" "\\{" "\\*" "\\+" "\\?" "\\|" "\\^" "\\$" ]
              [ "" "" "" "" "" "" "" "" "" "" "" "" ]
              posixPattern;
            posixCompilable =
              builtins.match ".*[[{].*" p == null
              && builtins.match ".*\\(\\?.*" p == null
              && builtins.match ".*\\\\.*" peeled == null;
          in
          if !posixCompilable then
            base
          else
            lib.types.addCheck base (x: builtins.match posixPattern x != null)
            // {
              description = "''${base.description} (matching `''${p}`)";
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
          _priority = mkOption { type = types.nullOr types.int; default = null; internal = true; };
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
    buildInputs = [ pkgs.nixfmt ];
  }
  ''
    cat << 'GENERATED' > ./raw.nix
    ${generated}
    GENERATED

    nixfmt ./raw.nix
    cp ./raw.nix $out
  ''
