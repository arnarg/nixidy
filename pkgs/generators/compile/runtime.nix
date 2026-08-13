# Runtime helpers for generated resource modules.
#
# These are the exact helper definitions that the text generator
# (./generator.nix) inlines, as source, into the `let` block of every
# generated `.nix` file. The native module builder (./module.nix) imports
# them as real values instead, so it can produce a module *value* directly
# without the generate-source-to-file-then-`import` round-trip.
#
# `definitions` is the generated definition set (`{ <ref> = { options; config; }; }`)
# and is threaded back in lazily — `submoduleOf` and friends only force it
# when an option is actually evaluated, so the mutual recursion between the
# helpers and `definitions` is fine.
{
  lib,
  config,
  definitions,
}:
with lib;
rec {
  hasAttrNotNull = attr: set: hasAttr attr set && set.${attr} != null;

  attrsToList =
    values:
    if values != null then
      sort (
        a: b:
        if (hasAttrNotNull "_priority" a && hasAttrNotNull "_priority" b) then
          a._priority < b._priority
        else
          false
      ) (mapAttrsToList (_n: v: v) values)
    else
      values;

  getDefaults =
    resource: group: version: kind:
    catAttrs "default" (
      filter (
        default:
        (default.resource == null || default.resource == resource)
        && (default.group == null || default.group == group)
        && (default.version == null || default.version == version)
        && (default.kind == null || default.kind == kind)
      ) config.defaults
    );

  types = lib.types // rec {
    str = mkOptionType {
      name = "str";
      description = "string";
      check = isString;
      merge = mergeEqualOption;
    };

    # Either value of type `finalType` or `coercedType`, the latter is
    # converted to `finalType` using `coerceFunc`.
    coercedTo =
      coercedType: coerceFunc: finalType:
      mkOptionType rec {
        inherit (finalType) getSubOptions getSubModules;

        name = "coercedTo";
        description = "${finalType.description} or ${coercedType.description}";
        check = x: finalType.check x || coercedType.check x;
        merge =
          loc: defs:
          let
            coerceVal =
              val:
              if finalType.check val then
                val
              else
                let
                  coerced = coerceFunc val;
                in
                assert finalType.check coerced;
                coerced;
          in
          finalType.merge loc (map (def: def // { value = coerceVal def.value; }) defs);
        substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
        typeMerge = _t1: _t2: null;
        functor = (defaultFunctor name) // {
          wrapped = finalType;
        };
      };

    # Numeric bounds.
    withMinimum =
      min: base:
      lib.types.addCheck base (x: x >= min)
      // {
        description = "${base.description} (minimum ${toString min})";
      };
    withMaximum =
      max: base:
      lib.types.addCheck base (x: x <= max)
      // {
        description = "${base.description} (maximum ${toString max})";
      };
    withExclusiveMinimum =
      min: base:
      lib.types.addCheck base (x: x > min)
      // {
        description = "${base.description} (exclusive minimum ${toString min})";
      };
    withExclusiveMaximum =
      max: base:
      lib.types.addCheck base (x: x < max)
      // {
        description = "${base.description} (exclusive maximum ${toString max})";
      };
    withMultipleOf =
      m: base:
      lib.types.addCheck base (x: mod x m == 0)
      // {
        description = "${base.description} (multiple of ${toString m})";
      };

    # String constraints.
    withMinLength =
      n: base:
      lib.types.addCheck base (x: stringLength x >= n)
      // {
        description = "${base.description} (min length ${toString n})";
      };
    withMaxLength =
      n: base:
      lib.types.addCheck base (x: stringLength x <= n)
      // {
        description = "${base.description} (max length ${toString n})";
      };
    withPattern =
      p: base:
      let
        # `builtins.match` compiles its pattern as a POSIX ERE, but JSON Schema
        # `pattern`s are ECMAScript. The two dialects diverge in many places, and
        # an unsupported construct makes `builtins.match` throw an *uncatchable*
        # error at compile time (`builtins.tryEval` does not rescue it) — for every
        # value, aborting evaluation of the whole environment. Since the throw
        # cannot be caught, we must decide *statically* whether a pattern is safe,
        # and we do so conservatively: translate the class escapes POSIX ERE lacks
        # (`\d`, `\s`, `\w` and their negations, plus `\/`) for the simple case,
        # then apply the check ONLY for patterns we can be sure compile, skipping
        # (returning the base `str`) otherwise. The API server validates the real
        # pattern regardless, so skipping only forgoes a redundant client check.
        #
        # We skip when the original pattern contains any of:
        #   - a character class `[…]` — POSIX bracket expressions have their own
        #     sub-syntax (`[[:class:]]`, `[.coll.]`, `[=eq=]`) and rules that
        #     diverge from ECMAScript, and `replaceStrings`-based escape
        #     translation is context-blind (it would corrupt an escape *inside* a
        #     class), so classes are out of scope;
        #   - a brace `{` — POSIX interval vs. ECMAScript literal-brace divergence;
        #   - a `(?…)` group — POSIX ERE has no such groups;
        #   - an unsupported backslash-escape — one that survives peeling off every
        #     escape POSIX ERE accepts (e.g. `\b`, `\-`, `\:`).
        # This is a coverage/robustness trade: it validates only the class-free
        # subset, but never crashes and never mis-validates a valid value. Anything
        # more (classes, intervals) is left to the API server.
        posixPattern =
          builtins.replaceStrings
            [
              "\\d"
              "\\D"
              "\\s"
              "\\S"
              "\\w"
              "\\W"
              "\\/"
            ]
            [
              "[0-9]"
              "[^0-9]"
              "[[:space:]]"
              "[^[:space:]]"
              "[0-9A-Za-z_]"
              "[^0-9A-Za-z_]"
              "/"
            ]
            p;
        peeled =
          builtins.replaceStrings
            [
              "\\\\"
              "\\."
              "\\("
              "\\)"
              "\\["
              "\\{"
              "\\*"
              "\\+"
              "\\?"
              "\\|"
              "\\^"
              "\\$"
            ]
            [
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
            ]
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
          description = "${base.description} (matching `${p}`)";
        };
  };

  mkOptionDefault = mkOverride 1001;

  mergeValuesByKey =
    attrMergeKey: listMergeKeys: values:
    listToAttrs (
      imap0 (
        i: value:
        nameValuePair (
          if hasAttr attrMergeKey value then
            if isAttrs value.${attrMergeKey} then
              toString value.${attrMergeKey}.content
            else
              (toString value.${attrMergeKey})
          else
            # generate merge key for list elements if it's not present
            "__kubenix_list_merge_key_"
            + (concatStringsSep "" (
              map (
                key: if isAttrs value.${key} then toString value.${key}.content else (toString value.${key})
              ) listMergeKeys
            ))
        ) (value // { _priority = i; })
      ) values
    );

  submoduleOf =
    ref:
    types.submodule (_: {
      options = definitions.${ref}.options or { };
      config = definitions.${ref}.config or { };
    });

  globalSubmoduleOf =
    ref:
    types.submodule (_: {
      options = config.definitions.${ref}.options or { };
      config = config.definitions.${ref}.config or { };
    });

  submoduleWithMergeOf =
    ref: mergeKey:
    types.submodule (
      { name, ... }:
      let
        convertName =
          name: if definitions.${ref}.options.${mergeKey}.type == types.int then toInt name else name;
      in
      {
        options = definitions.${ref}.options // {
          # position in original array
          _priority = mkOption {
            type = types.nullOr types.int;
            default = null;
            internal = true;
          };
        };
        config = definitions.${ref}.config // {
          ${mergeKey} = mkOverride 1002 (
            # use name as mergeKey only if it is not coming from mergeValuesByKey
            if (!hasPrefix "__kubenix_list_merge_key_" name) then convertName name else null
          );
        };
      }
    );

  submoduleForDefinition =
    ref: resource: kind: group: version:
    let
      apiVersion = if group == "core" then version else "${group}/${version}";
    in
    types.submodule (
      { name, ... }:
      {
        inherit (definitions.${ref}) options;

        imports = getDefaults resource group version kind;
        config = mkMerge [
          definitions.${ref}.config
          {
            kind = mkOptionDefault kind;
            apiVersion = mkOptionDefault apiVersion;

            # metdata.name cannot use option default, due deep config
            metadata.name = mkOptionDefault name;
          }
        ];
      }
    );

  coerceAttrsOfSubmodulesToListByKey =
    ref: attrMergeKey: listMergeKeys:
    (types.coercedTo (types.listOf (submoduleOf ref)) (mergeValuesByKey attrMergeKey listMergeKeys) (
      types.attrsOf (submoduleWithMergeOf ref attrMergeKey)
    ));
}
