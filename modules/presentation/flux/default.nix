# Minimal Flux presentation backend (raw-object proof).
#
# When `backend == "flux"`, synthesizes — as RAW object attrsets in the
# `__flux-system` synthetic app's `objects` — one shared `GitRepository`, one
# `Kustomization` per real public app, and a root `Kustomization` as the
# bootstrap equivalent. No Flux CRD type is registered: raw attrsets bypass the
# namespaced-default machinery, so every object sets its metadata (incl.
# namespace) fully. `__flux-system` is `__`-prefixed so `publicApps` excludes it
# (no self-presentation).
{ lib, config, ... }:
let
  cfg = config.nixidy;
  fluxNamespace = "flux-system";
  # The GitRepository source and the root Kustomization deliberately share this
  # name (distinct kinds, matching the `flux bootstrap` convention).
  sourceName = "flux-system";

  # `<rootPath>/<app.flux.path or app.output.path>`. `subpath.join` already
  # returns a normalized `./`-prefixed relative subpath (Flux's `spec.path`
  # convention) — matching the argocd backend's `present.nix` path idiom.
  syncPath =
    app:
    lib.path.subpath.join [
      cfg.target.rootPath
      (if app.flux.path != null then app.flux.path else app.output.path)
    ];

  gitRepository = {
    apiVersion = "source.toolkit.fluxcd.io/v1";
    kind = "GitRepository";
    metadata = {
      name = sourceName;
      namespace = fluxNamespace;
    };
    spec = {
      url = cfg.target.repository;
      ref.branch = cfg.target.branch;
      interval = "1m";
    };
  };

  mkKustomization = app: {
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
      path = syncPath app;
    };
  };

  # The bootstrap equivalent: a root Kustomization syncing the whole rootPath.
  # It and the per-app Kustomizations intentionally target overlapping paths
  # (root = all of rootPath; per-app = each app's subdir) — Flux reconciles both.
  rootKustomization = {
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
      path = lib.path.subpath.join [ cfg.target.rootPath ];
    };
  };
in
{
  config = lib.mkIf (cfg.presentation.backend == "flux") {
    # Per-application flux options (`applications.<name>.flux.*`).
    nixidy.presentation.perAppModules = [ ./options.nix ];

    # The Flux controller objects, synthesized as raw attrsets in a synthetic
    # `__`-prefixed app so they aren't presented to themselves.
    applications.__flux-system.objects = [
      gitRepository
    ]
    ++ map (name: mkKustomization config.applications.${name}) cfg.publicApps
    ++ [ rootKustomization ];
  };
}
