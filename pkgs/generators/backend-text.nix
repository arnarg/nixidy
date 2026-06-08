# Text backend for the shared schema walk (./walk.nix).
#
# Every combinator emits a fragment of Nix *source*. ./generator.nix assembles
# these into a standalone, committable `.nix` module file (the names referenced
# here — `submoduleOf`, `mkOption`, `types`, ... — are resolved by the runtime
# `let` block that generator.nix inlines into that file).
{ lib }:
with lib;
let
  # Escape ${...} sequences so they appear as literal text in generated
  # Nix "..." strings instead of being parsed as string interpolations.
  escapeNixStr = str: builtins.replaceStrings [ "\${" ] [ "\\$\{" ] str;

  toNixString =
    value:
    if isAttrs value || isList value then
      escapeNixStr (builtins.toJSON value)
    else if isString value then
      ''"${escapeNixStr value}"''
    else if value == null then
      "null"
    else
      builtins.toString value;

  removeEmptyLines =
    str:
    concatStringsSep "\n" (filter (l: builtins.match "[[:space:]]*" l != [ ]) (splitString "\n" str));
in
{
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
    either = val1: val2: "(types.either ${val1} ${val2})";
    loaOf = type: "(types.loaOf ${type})";
    # `walk` pre-maps the alternatives, so this receives rendered type strings.
    oneOf = ts: "(types.oneOf [${concatStringsSep " " ts}])";
  };

  mkOption =
    {
      description ? null,
      type ? null,
      default ? null,
      apply ? null,
    }:
    removeEmptyLines ''
      mkOption {
            ${optionalString (
              description != null
            ) "description = ${escapeNixStr (builtins.toJSON description)};"}
            ${optionalString (type != null) "type = ${type};"}
            ${optionalString (default != null) "default = ${toNixString default};"}
            ${optionalString (apply != null) "apply = ${apply};"}
          }'';

  mkOverrideNull = "mkOverride 1002 null";

  submoduleOf = ref: ''(submoduleOf "${ref}")'';

  globalSubmoduleOf = ref: ''(globalSubmoduleOf "${ref}")'';

  submoduleForDefinition =
    ref: name: kind: group: version:
    ''(submoduleForDefinition "${ref}" "${name}" "${kind}" "${group}" "${version}")'';

  coerceAttrsOfSubmodulesToListByKey =
    ref: attrMergeKey: listMergeKeys:
    ''(coerceAttrsOfSubmodulesToListByKey "${ref}" "${attrMergeKey}" [${
      concatStringsSep " " (map (key: "\"${toString key}\"") listMergeKeys)
    }])'';

  attrsToList = "attrsToList";
}
