# Minimal Flux presentation backend (raw-object proof).
#
# Synthesizes — as RAW object attrsets in the `__flux-system` synthetic app's
# `objects` — one shared `GitRepository`, one `Kustomization` per real public app,
# and a root `Kustomization` as the bootstrap equivalent. No Flux CRD type is
# registered: raw attrsets bypass the namespaced-default machinery, so every
# object sets its metadata (incl. namespace) fully. `__flux-system` is
# `__`-prefixed so `publicApps` excludes it (no self-presentation).
#
# The builders are pure functions of the synthesis `ctx` (target/apps); the
# registry entry below wires `present` to assemble them.
_:
let
  fluxNamespace = "flux-system";
  # The GitRepository source and the root Kustomization deliberately share this
  # name (distinct kinds, matching the `flux bootstrap` convention).
  sourceName = "flux-system";

  # `<rootPath>/<app.flux.path or app.output.path>`. `subpath.join` already
  # returns a normalized `./`-prefixed relative subpath (Flux's `spec.path`
  # convention) — matching the argocd backend's `present.nix` path idiom.
  syncPath =
    ctx: app:
    ctx.lib.path.subpath.join [
      ctx.target.rootPath
      (if app.flux.path != null then app.flux.path else app.output.path)
    ];

  gitRepository = ctx: {
    apiVersion = "source.toolkit.fluxcd.io/v1";
    kind = "GitRepository";
    metadata = {
      name = sourceName;
      namespace = fluxNamespace;
    };
    spec = {
      url = ctx.target.repository;
      ref.branch = ctx.target.branch;
      interval = "1m";
    };
  };

  mkKustomization = ctx: app: {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1";
    kind = "Kustomization";
    metadata = {
      name = app.name;
      namespace = fluxNamespace;
    };
    spec = {
      inherit (app.flux) interval prune;
      sourceRef = {
        kind = "GitRepository";
        name = sourceName;
      };
      path = syncPath ctx app;
    };
  };

  # The bootstrap equivalent: a root Kustomization syncing the whole rootPath.
  # It and the per-app Kustomizations intentionally target overlapping paths
  # (root = all of rootPath; per-app = each app's subdir) — Flux reconciles both.
  rootKustomization = ctx: {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1";
    kind = "Kustomization";
    metadata = {
      name = sourceName;
      namespace = fluxNamespace;
    };
    spec = {
      interval = "10m";
      prune = true;
      sourceRef = {
        kind = "GitRepository";
        name = sourceName;
      };
      path = ctx.lib.path.subpath.join [ ctx.target.rootPath ];
    };
  };
in
{
  # Register the Flux backend unconditionally; the dispatcher (../default.nix)
  # threads this record in only when `nixidy.presentation.backend == "flux"`.
  config.nixidy.presentation.backends.flux = {
    # Per-application flux options (`applications.<name>.flux.*`).
    perAppOptions = [ ./options.nix ];

    # The Flux controller objects, synthesized as raw attrsets in a synthetic
    # `__`-prefixed app so they aren't presented to themselves.
    present = ctx: {
      __flux-system.objects = [
        (gitRepository ctx)
      ]
      ++ map (name: mkKustomization ctx ctx.apps.${name}) ctx.publicApps
      ++ [ (rootKustomization ctx) ];
    };
  };
}
