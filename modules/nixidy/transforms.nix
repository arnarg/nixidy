{ lib }:
let
  inherit (lib) types mkOption;

  selectorType = types.submodule {
    options = {
      kind = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      apiVersion = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      namespace = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      labels = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      annotations = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };
  };

  # selector attrset -> (resource -> bool); present fields ANDed,
  # labels/annotations are SUBSET match (extra keys on the resource are fine).
  selectorToPredicate =
    sel: res:
    let
      m = res.metadata or { };
      eq = field: val: val == null || field == val;
      hasAll = have: want: lib.all (k: (have.${k} or null) == want.${k}) (lib.attrNames want);
    in
    eq (res.kind or null) (sel.kind or null)
    && eq (res.apiVersion or null) (sel.apiVersion or null)
    && eq (m.namespace or null) (sel.namespace or null)
    && eq (m.name or null) (sel.name or null)
    && hasAll (m.labels or { }) (sel.labels or { })
    && hasAll (m.annotations or { }) (sel.annotations or { });

  ruleType = types.submodule (
    { config, ... }:
    {
      options = {
        match = mkOption {
          type = types.either (types.functionTo types.bool) selectorType;
          default = _: true;
          description = "Resource predicate, or a declarative selector that desugars to one.";
        };
        map = mkOption {
          type = types.nullOr (types.functionTo (types.nullOr (types.attrsOf types.anything)));
          default = null;
          description = "Eval-time transform: resource -> resource (or null to drop).";
        };
        render = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                runtimeInputs = mkOption {
                  type = types.listOf types.package;
                  default = [ ];
                };
                command = mkOption {
                  type = types.either types.lines (types.functionTo types.lines);
                  description = ''
                    Runtime stage producing final on-disk content.
                    stdin  = store content for the matched file
                    stdout = content written to disk
                    env    = $TARGET_PATH (existing file path; may not exist)

                    Either a literal shell snippet, or a function resolved at
                    eval time against the matched object:
                      { resource, path, pkgs, lib }: <shell snippet>
                    where `resource` is the post-map object, `path` its on-disk
                    relative path. Use this to specialize the command per object
                    (e.g. choose a recipient key from `resource.metadata.namespace`)
                    instead of re-parsing the manifest on stdin.
                  '';
                };
              };
            }
          );
          default = null;
          description = "Runtime stage rendering the final on-disk artifact for the matched file.";
        };
        predicate = mkOption {
          internal = true;
          readOnly = true;
          type = types.functionTo types.bool;
          default = if lib.isFunction config.match then config.match else selectorToPredicate config.match;
        };
      };
    }
  );
in
{
  inherit ruleType selectorToPredicate;
}
