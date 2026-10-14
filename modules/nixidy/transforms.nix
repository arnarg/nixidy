{ lib }:
let
  inherit (lib)
    types
    mkOption
    toList
    optionalAttrs
    concatStringsSep
    mapAttrsToList
    ;
  inherit (builtins)
    isAttrs
    isList
    any
    attrValues
    filter
    length
    concatLists
    ;

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

  selectorToPredicate =
    sel: res:
    let
      matchAttr =
        res:
        { name, value }:
        let
          resValue = res.${name} or null;
        in
        if (value == null) != (resValue == null) then
          false
        else if isAttrs resValue then
          matchAttrs value resValue
        else if isList resValue then
          any (matchAttrs value) resValue
        else if isList value then
          any (s: s == resValue) value
        else
          value == resValue;
      matchAttrs =
        sel: res:
        if isList sel then any (s: matchAttrs s res) sel else lib.all (matchAttr res) (lib.attrsToList sel);
    in
    matchAttrs sel res;

  postProcessorType = types.submodule (
    { name, config, ... }:
    {
      options = {
        match = mkOption {
          type = types.oneOf [
            (types.functionTo types.bool)
            types.attrs
            (types.listOf types.attrs)
          ];
          default = _: true;
          description = ''
            Apply rewrite only to resources that match this predicate.

            The predicate can either be a function `resource -> bool` or an attrset—in such case it will match when it's a subset of the part.
            This also looks for any matching item in an array, so that e. g. in a Pod, `spec.containers.envFrom.secretRef.name = "foo";`
            will match any pod with a container that has an envFrom with `secretRef.name == "foo"`.

            Attribute checks are ANDed, but you can OR matches by providing an array, such as: `secretRef.name = [ "foo" "bar" ];`.

            By default, all resources match.
          '';
        };
        runtimeInputs = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = "Packages added to the post-process command's PATH.";
        };
        command = mkOption {
          type = types.either types.lines (types.functionTo types.lines);
          description = ''
            Runtime stage producing final on-disk content.
            stdin  = store content for the matched file
            stdout = content written to disk
            env    = $TARGET_PATH (absolute existing file path; may not exist; switch only)

            stdin/stdout is the contract so stages compose as a pipe, but the
            command body is arbitrary shell. For a tool that needs a real file
            path (e.g. `sops -i`, `yq -i`), capture stdin to a temp file and emit
            it back: `f=$(mktemp); cat > "$f"; sops -e -i "$f"; cat "$f"`.

            Either a literal shell snippet, or a function resolved at eval time
            against the matched object:
            ```nix
            { resource, path, pkgs, lib }: <shell snippet>
            ```
            where `resource` is the post-rewrite object and `path` its on-disk
            relative path. `path` is identical on the `switch` and `apply` paths,
            so a `path`-using command resolves the same on both. `$TARGET_PATH`
            (the absolute destination) is set only on `switch`/activation; on
            `apply` there is no on-disk target and it is unset. Use the function
            form to specialize the command per object (e.g. choose a recipient key
            from `resource.metadata.namespace`) instead of re-parsing the manifest
            on stdin.
          '';
        };
        name = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
          default = name;
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

  objectTransformType = types.submodule (
    { name, config, ... }:
    {
      options = {
        path = mkOption {
          type = (types.listOf types.str);
          default = [ ];
          description = ''
            Path to a part of the resource you want to replace with `value`.

            If a path element is a list, the transform is applied to each element of that list.
            That is, in a Pod, `[ "spec" "containers" "env" ]` would apply the transform to
            each `env` entry inside each `containers` entry.
          '';
        };
        match = mkOption {
          type = types.oneOf [
            (types.functionTo types.bool)
            types.attrs
            (types.listOf types.attrs)
          ];
          default = _: true;
          description = ''
            Apply the transform only to resources (or their parts as specified by `path`) that match this predicate.

            The predicate can either be a function `resource -> bool` or an attrset—in such case it will match when it's a subset of the part.
            This also looks for any matching item in an array, so that e. g. in a Pod, `spec.containers.envFrom.secretRef.name = "foo";`
            will match any pod with a container that has an envFrom with `secretRef.name == "foo"`.

            Attribute checks are ANDed, but you can OR matches by providing an array, such as: `secretRef.name = [ "foo" "bar" ];`.

            By default, all resource match.
          '';
        };
        replace = mkOption {
          type = types.nullOr (types.coercedTo types.anything (v: _: v) (types.functionTo types.anything));
          default = null;
          description = ''
            Replaces the object with either:
              * null, which drops the object,
              * a plain value
              * a function taking the old value as the argument and returning a new one.

            Only one of `replace`, `update` or `transform` can be set.
          '';
        };
        update = mkOption {
          type = types.nullOr (types.coercedTo types.attrs (v: _: v) (types.functionTo types.attrs));
          default = null;
          description = ''
            Recursively updates the object with either:
              * the attrset provided
              * a function taking the old value as the argument and a new attrset (that's merged with the old one).

            Only one of `replace`, `update` or `transform` can be set.
          '';
        };
        transforms = mkOption {
          type = types.nullOr (types.attrsOf objectTransformType);
          default = null;
          description = ''
            An attrset of sub-transforms. `transform.<name>.path` starts at the object matched by `path`.

            Only one of `replace`, `update` or `transform` can be set.
          '';
        };
        name = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
          default = name;
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

  mkObjectTransformsOption =
    description:
    mkOption {
      type = types.attrsOf objectTransformType;
      default = { };
      inherit description;
    };

  mkPostProcessorsOption =
    description:
    mkOption {
      type = types.attrsOf postProcessorType;
      default = { };
      description = ''
        ${description}

        Post processors run and activation time and produce the final on-disk artifact
        for the matched file (a stdin -> stdout filter).

        !!! warning
            `postProcessors` commands run at activation time, outside any sandbox,
            with the privileges of whoever runs `nixidy switch`. A `postProcessors`
            rule from a configuration you have not vetted is arbitrary code
            execution on `switch`. To surface this, `switch` prints the commands
            it is about to run and, when attached to a terminal, pauses for
            confirmation (`NIXIDY_POST_PROCESS_APPROVE=1` skips the prompt;
            `NIXIDY_SKIP_POST_PROCESS=1` reuses the already-rendered target files
            without running anything). These are visibility aids, not a security
            boundary as the configuration that defines the rule can also set the
            approval variable.

            `nixidy apply` also runs `postProcessors`: its `apply` script consumes
            the same `environmentPackage` the switch path renders and streams
            each resource through the chain before `kubectl apply`, so `switch`
            and `apply` deploy the same manifests. The chain output must be a
            valid cluster manifest. A transform whose result only a GitOps
            controller can consume (e.g. a ksops / whole-document-encrypted
            file) is switch-only; `kubectl apply` rejects it. The same
            visibility/prompt applies on `apply`, but `NIXIDY_SKIP_POST_PROCESS`
            is NOT honored there (no rendered target to fall back to) and the chain
            always runs. The build outputs of `environmentPackage` /
            `declarativePackage` still contain the pre-`postProcessors` manifests
            (the transform is runtime-only); keep real secret material out of
            nixidy resources (use references), as rendered values land in the
            world-readable nix store regardless.
      '';
    };
  # Build the "exactly one of rewrite/postProcess" assertions for a list of
  # rules. `scope` is the option path used to prefix each message; a rule's
  # optional `name` is appended so the offender is identifiable.
  mkXorAssertions =
    scope: rules:
    let
      namedRule = path: rule: {
        inherit rule;
        name = concatStringsSep "." path;
      };
      transforms = rule: optionalAttrs (rule.transforms != null) rule.transforms;
      # Return a flattened list of all transforms, including ones nested in other transforms.
      allTransforms =
        path: rules:
        concatLists (
          mapAttrsToList (
            name: rule:
            [ (namedRule (path ++ [ name ]) rule) ] ++ (allTransforms (path ++ [ name ]) (transforms rule))
          ) rules
        );
    in
    map (
      { name, rule }:
      {
        # If all are null, we assume that replace was deliberately set to null.
        assertion =
          lib.pipe rule [
            (lib.attrVals [
              "replace"
              "update"
              "transforms"
            ])
            (filter (v: v != null))
            length
          ] <= 1;
        message = "${scope} transform ${name}: exactly one of `replace`, `update`, `transform` can be set.";
      }
    ) (allTransforms [ ] rules);
in
{
  inherit
    mkObjectTransformsOption
    mkPostProcessorsOption
    selectorToPredicate
    mkXorAssertions
    ;
}
