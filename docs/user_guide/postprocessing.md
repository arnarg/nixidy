# Post-processing rendered files

Post-processors attach a stage that runs when the environment is applied, _after_ the object has been rendered to its file. They are a **stdin → stdout filter**: the rendered manifest is fed in on stdin and whatever they write to stdout becomes the final content.

A bare string is the common case, a single command with no extra packages on its `PATH`:

```nix
{
    nixidy.postProcessors.foo = {
      match.kind = "ConfigMap";
      command = "yq -P 'sort_keys(..)'";
    };
}
```

You can also specify `runtimeInputs` that add packages to the command's `PATH`, and define the command as a function resolved at evaluation time against the matched object, which lets you specialise the command per object without re-parsing the manifest:

```nix
{
  match.kind = "SopsSecret";
  runtimeInputs = [ pkgs.sops ];
  command =
    { resource, ... }:
    "sops --encrypt --input-type yaml --output-type yaml /dev/stdin";
}
```

The command body is arbitrary shell, so a tool that needs a real file path (`sops -i`, `yq -i`) can capture stdin to a temporary file and emit it back:

```nix
{
  command = ''
    f=$(mktemp)
    cat > "$f"
    sops --encrypt --in-place "$f"
    cat "$f"
  '';
}
```

!!! info
    Post-processors run **outside** the evaluation sandbox on purpose, so they can reach things a `replace` cannot such as the network, a hardware key, or host tools. That is the whole reason it is a separate stage and not a `replace`. `$TARGET_PATH` (the absolute destination path) is available at runtime on `switch`.

## Visibility and safety

Because commands run with the privileges of whoever runs `nixidy switch`, applying a configuration you have not vetted is arbitrary code execution. To make this visible, `nixidy switch` prints every command it is about to run, resolved against its matched object, and when attached to a terminal, pauses for confirmation:

```sh
post-processing 1 manifest file(s); the following commands run outside any sandbox. Review them before continuing:
  myapp/SopsSecret-db.yaml:
    encrypt-secrets: sops --encrypt --input-type yaml --output-type yaml /dev/stdin
Continue with post-processing? [y/N]
```

A piped, CI or pre-commit run is non-interactive and proceeds without prompting, so automation never blocks. Two environment variables tune the behaviour:

- `NIXIDY_POST_PROCESS_APPROVE=1` skips the prompt for trusted, repeated interactive use.
- `NIXIDY_SKIP_POST_PROCESS=1` reuses the already-rendered target files without running anything. This can be useful in an environment that lacks the post-process toolchain or secrets (for example, CI re-rendering manifests).

!!! warning
    These are visibility aids, **not** a security boundary and a configuration that defines a `postProcessors` rule can also set the approval variable. The point is to surface arbitrary execution to a human, not to sandbox it.

## Applying directly

[`nixidy apply`](direct_apply.md) runs `postProcessors` too, so applying directly deploys the same manifests as `nixidy switch`. Each object is streamed through its post-process command and piped to `kubectl apply`. The same notice and confirmation prompt run before anything is applied, and `NIXIDY_POST_PROCESS_APPROVE=1` skips it.

!!! warning
    A command's output must be a valid Kubernetes manifest for `nixidy apply` to deploy it. A post-processor whose output only a GitOps controller can consume (for example a ksops, fully-encrypted file) is `switch`-only and `kubectl apply` will reject it. `NIXIDY_SKIP_POST_PROCESS` is not honoured on `apply`, since there is no rendered target to fall back to; the command always runs. `$TARGET_PATH` is set only on `switch`.

## Ordering and scoping

Environment rules run first, then the matched application's rules, in the alphabetical order of their attribute names within each.
