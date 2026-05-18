{ lib, config, ... }:
let
  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  gvkKeyFn = type: "${type.group}/${type.version}/${type.kind}";

  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  coerceListOfSubmodulesToAttrs =
    with lib;
    submodule: keyFn:
    let
      mergeValuesByFn =
        keyFn: values: listToAttrs (map (value: nameValuePair (toString (keyFn value)) value) values);

      # Either value of type `finalType` or `coercedType`, the latter is
      # converted to `finalType` using `coerceFunc`.
      coercedTo =
        coercedType: coerceFunc: finalType:
        mkOptionType rec {
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
          inherit (finalType) getSubOptions;
          inherit (finalType) getSubModules;
          substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
          typeMerge = _t1: _t2: null;
          functor = (defaultFunctor name) // {
            wrapped = finalType;
          };
        };
    in
    coercedTo (types.listOf (types.submodule submodule)) (mergeValuesByFn keyFn) (
      types.attrsOf (types.submodule submodule)
    );

  # Copied from https://github.com/hall/kubenix/blob/main/modules/k8s.nix
  moduleToAttrs =
    with lib;
    value:
    if isAttrs value then
      mapAttrs (_n: moduleToAttrs) (filterAttrs (n: v: v != null && !(hasPrefix "_priority" n)) value)
    else if isList value then
      map moduleToAttrs value
    else
      value;
in
{
  options = with lib; {
    definitions = mkOption {
      description = "Attribute set of kubernetes definitions";
      internal = true;
    };
    defaults = mkOption {
      description = "Kubernetes defaults to apply to resources";
      type = types.listOf (
        types.submodule (_: {
          options = {
            group = mkOption {
              description = "Group to apply default to (all by default)";
              type = types.nullOr types.str;
              default = null;
              internal = true;
            };

            version = mkOption {
              description = "Version to apply default to (all by default)";
              type = types.nullOr types.str;
              default = null;
              internal = true;
            };

            kind = mkOption {
              description = "Kind to apply default to (all by default)";
              type = types.nullOr types.str;
              default = null;
              internal = true;
            };

            resource = mkOption {
              description = "Resource to apply default to (all by default)";
              type = types.nullOr types.str;
              default = null;
              internal = true;
            };

            propagate = mkOption {
              description = "Whether to propagate defaults";
              type = types.bool;
              default = false;
              internal = true;
            };

            default = mkOption {
              description = "Default to apply";
              type = types.unspecified;
              default = { };
              internal = true;
            };
          };
        })
      );
      default = [ ];
      apply = unique;
      internal = true;
    };
    types = mkOption {
      description = "List of registered kubernetes types";
      type = coerceListOfSubmodulesToAttrs {
        options = {
          group = mkOption {
            description = "Resource type group";
            type = types.str;
            internal = true;
          };
          version = mkOption {
            description = "Resoruce type version";
            type = types.str;
            internal = true;
          };
          kind = mkOption {
            description = "Resource type kind";
            type = types.str;
            internal = true;
          };
          name = mkOption {
            description = "Resource type name";
            type = types.nullOr types.str;
            internal = true;
          };
          attrName = mkOption {
            description = "Name of the nixified attribute";
            type = types.str;
            internal = true;
          };
        };
      } gvkKeyFn;
      default = { };
      internal = true;
    };
    objects = mkOption {
      type = with types; listOf attrs;
      apply = unique;
      default = [ ];
      internal = true;
    };
  };

  config = {
    # Turn all typed resources into standard kubernetes
    # objects that will be written to YAML files.
    objects =
      with lib;
      flatten (
        mapAttrsToList (
          _: type:
          mapAttrsToList (_: moduleToAttrs) config.resources.${type.group}.${type.version}.${type.kind}
        ) config.types
      );
  };
}
