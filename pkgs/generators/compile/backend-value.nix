# Value backend for the shared schema walk (./walk.nix).
#
# Every combinator returns a live value (an option, a type, a submodule). It
# simply adapts the runtime helpers (./runtime.nix, `rt`) and `lib` into the
# backend interface the walk expects. ./module.nix assembles the walk output
# into a module value directly — no source, no file, no import IFD.
{ lib, rt }:
{
  # rt.types is `lib.types` with the custom `str`/`coercedTo` overrides the
  # generated modules rely on; it already provides int/listOf/oneOf/loaOf/etc.
  inherit (rt)
    types
    submoduleOf
    globalSubmoduleOf
    coerceAttrsOfSubmodulesToListByKey
    submoduleForDefinition
    attrsToList
    ;

  mkOption = lib.mkOption;
  mkOverrideNull = lib.mkOverride 1002 null;
}
