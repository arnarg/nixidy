# Object Transforms

Object transforms are a declarative rule engine for modifying rendered Kubernetes objects across your whole environment. A rule matches objects and either **rewrites** them while nixidy is still evaluating, or **post-processes** their rendered file content when the environment is applied. They are useful for cluster-wide policy (injecting labels or annotations, rewriting a kind, dropping resources) and for runtime content stages (such as piping a manifest through an external encryptor before it is written).

Rules can be set environment-wide in `#!nix nixidy.objectTransforms`, or per application in `#!nix applications.<name>.objectTransforms`:

```nix
{
  nixidy.objectTransforms = [
    # applied to every application's objects
  ];

  applications.my-app.objectTransforms = [
    # applied only to my-app's objects
  ];
}
```

Where [Transformers](transformers.md) act on a single Helm release or Kustomize application, object transforms are matched against objects from _all_ applications, so they are a good fit for policy you want to apply consistently across an environment.

## A rule

Each rule selects objects with `match` and sets exactly one of `rewrite` or `postProcess`:

```nix
{
  name = "encrypt-secrets";   # optional; shown in assertion messages and the post-process log
  match.kind = "Secret";      # predicate or selector; omit to match every object

  # exactly one of the following:
  rewrite = resource: resource;                 # evaluation-time transform
  postProcess = "<command>";                    # activation-time stdin -> stdout filter
}
```

## Matching resources

`match` is either a predicate `#!nix resource -> bool` or a declarative selector that desugars to one:

```nix
{
  # selector form
  match = {
    kind = "Secret";
    namespace = "default";
    labels."app.kubernetes.io/managed-by" = "nixidy";
  };

  # equivalent predicate form
  match = resource: resource.kind == "Secret";
}
```

Selector fields are ANDed together. `kind`, `apiVersion`, `namespace` and `name` match by exact equality, where a `#!nix null` field is a wildcard. `labels` and `annotations` are **subset** matches — the object may carry extra keys. The default matches _every_ object in scope, so omitting `match` applies the rule cluster-wide.

!!! note
    A rule's predicate runs against the object _as seen at that point in the pipeline_, i.e. after earlier rules' `rewrite`s. A rule that renames a kind must be matched by its **new** kind in any later rule.

## Rewriting objects

`rewrite` is an evaluation-time function `#!nix resource -> resource`. Returning `#!nix null` drops the object entirely. Because it runs during evaluation, the result feeds every output consistently — both `nixidy switch` and `nixidy apply` see the rewritten object.

```nix
{
  nixidy.objectTransforms = [
    # Add a managed-by label to every object in the environment.
    {
      rewrite =
        resource:
        resource
        // {
          metadata = resource.metadata // {
            labels = (resource.metadata.labels or { }) // {
              "app.kubernetes.io/managed-by" = "nixidy";
            };
          };
        };
    }

    # Drop every HorizontalPodAutoscaler.
    {
      match.kind = "HorizontalPodAutoscaler";
      rewrite = _: null;
    }
  ];
}
```

## Post-processing rendered files

`postProcess` attaches a stage that runs when the environment is applied, _after_ the object has been rendered to its file. It is a **stdin → stdout filter**: the rendered manifest is fed in on stdin and whatever it writes to stdout becomes the final content.

A bare string is the common case — a single command with no extra packages on its `PATH`:

```nix
{
  match.kind = "ConfigMap";
  postProcess = "yq -P 'sort_keys(..)'";
}
```

The full form adds `runtimeInputs` (packages placed on the command's `PATH`) and accepts a function resolved at evaluation time against the matched object, which lets you specialise the command per object without re-parsing the manifest:

```nix
{
  match.kind = "SopsSecret";
  postProcess = {
    runtimeInputs = [ pkgs.sops ];
    command =
      { resource, ... }:
      "sops --encrypt --input-type yaml --output-type yaml /dev/stdin";
  };
}
```

The command body is arbitrary shell, so a tool that needs a real file path (`sops -i`, `yq -i`) can capture stdin to a temporary file and emit it back:

```nix
{
  postProcess = ''
    f=$(mktemp)
    cat > "$f"
    sops --encrypt --in-place "$f"
    cat "$f"
  '';
}
```

!!! info
    `postProcess` runs **outside** the evaluation sandbox on purpose, so it can reach things a `rewrite` cannot — the network, a hardware key, or host tools. That is the whole reason it is a separate stage and not a `rewrite`. `$TARGET_PATH` (the absolute destination path) is available at runtime on `switch`.

### Visibility and safety

Because `postProcess` commands run with the privileges of whoever runs `nixidy switch`, applying a configuration you have not vetted is arbitrary code execution. To make this visible, `nixidy switch` prints every command it is about to run — resolved against its matched object — and, when attached to a terminal, pauses for confirmation:

```sh
post-processing 1 manifest file(s); the following commands run outside any sandbox — review them before continuing:
  apps/SopsSecret-db.yaml:
    encrypt-secrets: sops --encrypt --input-type yaml --output-type yaml /dev/stdin
Continue with post-processing? [y/N]
```

A piped, CI or pre-commit run is non-interactive and proceeds without prompting, so automation never blocks. Two environment variables tune the behaviour:

- `NIXIDY_POST_PROCESS_APPROVE=1` skips the prompt for trusted, repeated interactive use.
- `NIXIDY_SKIP_POST_PROCESS=1` reuses the already-rendered target files without running anything — for an environment that lacks the post-process toolchain (for example, CI re-rendering manifests).

!!! warning
    These are visibility aids, **not** a security boundary — a configuration that defines a `postProcess` rule can also set the approval variable. The point is to surface arbitrary execution to a human, not to sandbox it.

## Applying directly

[`nixidy apply`](direct_apply.md) runs `postProcess` too, so applying directly deploys the same manifests as `nixidy switch`. Each object is streamed through its post-process command and piped to `kubectl apply`. The same notice and confirmation prompt run before anything is applied, and `NIXIDY_POST_PROCESS_APPROVE=1` skips it.

!!! warning
    A `postProcess` command's output must be a valid Kubernetes manifest for `nixidy apply` to deploy it. A transform whose result only a GitOps controller can consume (for example a ksops, fully-encrypted file) is `switch`-only — `kubectl apply` will reject it. `NIXIDY_SKIP_POST_PROCESS` is not honoured on `apply`, since there is no rendered target to fall back to; the command always runs. `$TARGET_PATH` is set only on `switch`.

## Ordering and scoping

Environment rules run first, then the matched application's rules, in declaration order within each. A rule must set exactly one of `rewrite` or `postProcess`; setting both, or neither, fails evaluation with an assertion that names the offending rule.
