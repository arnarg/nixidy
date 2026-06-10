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

  # Runtime post-process stage. A bare string is the common case (one command,
  # no extra PATH) and coerces to `{ command = <string>; runtimeInputs = []; }`,
  # matching the `files` library's `onChange` ergonomics.
  postProcessType = types.submodule {
    options = {
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
    };
  };

  ruleType = types.submodule (
    { config, ... }:
    {
      options = {
        name = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Optional label for this rule, surfaced in assertion messages and
            the activation post-process log. Helps identify a rule among many
            and is purely diagnostic.
          '';
        };
        match = mkOption {
          type = types.either (types.functionTo types.bool) selectorType;
          default = _: true;
          description = ''
            Which resources this rule applies to: a predicate `resource -> bool`,
            or a declarative selector that desugars to one.

            Selector fields are ANDed. `kind`/`apiVersion`/`namespace`/`name`
            match by exact equality (a `null` field is a wildcard); `labels`/
            `annotations` are SUBSET matches (the resource may carry extra keys;
            the default `{ }` matches anything).

            The default matches EVERY resource in scope meaning that omitting
            `match` on a `rewrite`/`postProcess` rule applies it cluster-wide.
            Set `match` unless that is intended.

            Predicates run against the resource as seen at this point in the
            pipeline, i.e. AFTER earlier rules' `rewrite`s. A rule that renames
            a kind must be matched by its NEW kind in later rules.
          '';
        };
        rewrite = mkOption {
          type = types.nullOr (types.functionTo (types.nullOr (types.attrsOf types.anything)));
          default = null;
          description = ''
            Eval-time transform `resource -> resource`. Returning `null` drops
            the resource. Exactly one of `rewrite`/`postProcess` must be set.
          '';
        };
        postProcess = mkOption {
          type = types.nullOr (types.coercedTo types.lines (command: { inherit command; }) postProcessType);
          default = null;
          description = ''
            Activation-time stage producing the final on-disk artifact for the
            matched file (a stdin -> stdout filter). Exactly one of
            `rewrite`/`postProcess` must be set.

            ::: warning
            `postProcess` commands run at activation time, outside any sandbox,
            with the privileges of whoever runs `nixidy switch`. A `postProcess`
            rule from a configuration you have not vetted is arbitrary code
            execution on `switch`. To surface this, `switch` prints the commands
            it is about to run and, when attached to a terminal, pauses for
            confirmation (`NIXIDY_POST_PROCESS_APPROVE=1` skips the prompt;
            `NIXIDY_SKIP_POST_PROCESS=1` reuses the already-rendered target files
            without running anything). These are visibility aids, not a security
            boundary as the configuration that defines the rule can also set the
            approval variable.

            `nixidy apply` also runs `postProcess`: its `apply` script consumes
            the same `environmentPackage` the switch path renders and streams
            each resource through the chain before `kubectl apply`, so `switch`
            and `apply` deploy the same manifests. The chain output must be a
            valid cluster manifest. A transform whose result only a GitOps
            controller can consume (e.g. a ksops / whole-document-encrypted
            file) is switch-only; `kubectl apply` rejects it. The same
            visibility/prompt applies on `apply`, but `NIXIDY_SKIP_POST_PROCESS`
            is NOT honored there (no rendered target to fall back to) and the chain
            always runs. The build outputs of `environmentPackage` /
            `declarativePackage` still contain the pre-`postProcess` manifests
            (the transform is runtime-only); keep real secret material out of
            nixidy resources (use references), as rendered values land in the
            world-readable nix store regardless.
            :::
          '';
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
  # Build the "exactly one of rewrite/postProcess" assertions for a list of
  # rules. `scope` is the option path used to prefix each message; a rule's
  # optional `name` is appended so the offender is identifiable.
  mkXorAssertions =
    scope: rules:
    lib.imap0 (i: r: {
      assertion = (r.rewrite != null) != (r.postProcess != null);
      message =
        "${scope} rule ${toString i}"
        + lib.optionalString (r.name != null) " (`${r.name}`)"
        + ": set exactly one of `rewrite` or `postProcess`.";
    }) rules;
in
{
  inherit ruleType selectorToPredicate mkXorAssertions;
}
