# Pure-`present` unit tests: assert each backend's `present` function directly
# with a fixture `ctx`. Task 2 made `present :: ctx -> attrsOf appConfig` a pure
# synthesis seam that reads only OPTION-SET leaf fields of `ctx.apps.<name>`
# (namespace, output.path, argocd.*/flux.*) — never `resources.applications` /
# `objects`. So we can project a fixture `ctx` out of a fully-evaluated 2-app
# config and call `present ctx` directly, no dispatcher round-trip.
#
# Two cases, one per backend. Each case is evaluated by modules/testing/eval.nix
# as its own config (with the matching `backend`), and asserts on the value its
# backend's `present` returns for a ctx projected from that config.
#
# This file returns a *list* of two test modules; tests/default.nix splices them
# into `testing.tests` so they register as two independent cases.
let
  # Project the read-only synthesis ctx out of an evaluated config — the exact
  # shape modules/presentation/default.nix hands to a backend's `present`.
  mkCtx = lib: cfg: {
    target = { inherit (cfg.nixidy.target) repository branch rootPath; };
    inherit (cfg.nixidy) env appendNameWithEnv publicApps;
    apps = cfg.applications;
    inherit lib;
  };

  sortStr = lib: lib.sort (a: b: a < b);

  # --- ArgoCD case: backend=argocd, assert app-of-apps + __bootstrap. ---
  argocdCase =
    { lib, config, ... }:
    let
      ctx = mkCtx lib config;
      argocdName = config.nixidy.presentation.argocd.name; # default "apps"
      out = config.nixidy.presentation.backends.argocd.present ctx;

      # The public apps this test declares (the app-of-apps app is synthesized
      # by `present`, so it is excluded from the per-app expectation).
      realPublicApps = lib.filter (n: n != argocdName) config.nixidy.publicApps;

      appOfApps = out.${argocdName};
      bootstrap = out.__bootstrap;
    in
    {
      nixidy.presentation.backend = "argocd";

      applications.myapp1 = {
        namespace = "ns1";
        resources.configMaps.cm.data.x = "y";
      };
      applications.myapp2 = {
        namespace = "ns2";
        resources.configMaps.cm.data.a = "b";
      };

      test = {
        name = "argocd present unit";
        description = "argocd backend's pure `present` synthesizes the app-of-apps + __bootstrap apps from a fixture ctx";
        assertions = [
          {
            description = "app-of-apps app's resources.applications has an entry per real public app";
            expression = {
              appNames = sortStr lib (lib.attrNames appOfApps.resources.applications);
              expectedAppNames = sortStr lib realPublicApps;
            };
            assertion =
              v:
              v.appNames == v.expectedAppNames
              &&
                v.appNames == [
                  "myapp1"
                  "myapp2"
                ];
          }
          {
            description = "__bootstrap.resources.applications.<apps-name> is the app-of-apps Application";
            expression = bootstrap.resources.applications.${argocdName};
            assertion =
              app:
              app.metadata.name == argocdName
              && app.spec.source.repoURL == ctx.target.repository
              && app.spec.destination.namespace == config.nixidy.presentation.argocd.namespace;
          }
        ];
      };
    };

  # --- Flux case: backend=flux, assert __flux-system.objects. ---
  fluxCase =
    { lib, config, ... }:
    let
      ctx = mkCtx lib config;
      out = config.nixidy.presentation.backends.flux.present ctx;
      objects = out.__flux-system.objects;

      byKind = kind: lib.filter (o: (o.kind or null) == kind) objects;
      gitRepos = byKind "GitRepository";
      kustomizations = byKind "Kustomization";
      # The root Kustomization shares the source name ("flux-system"); the
      # per-app ones are named after each public app.
      rootKust = lib.filter (k: (k.metadata.name or null) == "flux-system") kustomizations;
      appKusts = lib.filter (k: (k.metadata.name or null) != "flux-system") kustomizations;
    in
    {
      nixidy.presentation.backend = "flux";

      applications.myapp1 = {
        namespace = "ns1";
        resources.configMaps.cm.data.x = "y";
      };
      applications.myapp2 = {
        namespace = "ns2";
        resources.configMaps.cm.data.a = "b";
      };

      test = {
        name = "flux present unit";
        description = "flux backend's pure `present` synthesizes GitRepository + per-app Kustomizations + root Kustomization from a fixture ctx";
        assertions = [
          {
            description = "__flux-system.objects carries exactly one GitRepository";
            expression = lib.length gitRepos;
            expected = 1;
          }
          {
            description = "one Kustomization per public app, named after each app";
            expression = {
              appKustNames = sortStr lib (map (k: k.metadata.name) appKusts);
              publicApps = sortStr lib config.nixidy.publicApps;
            };
            assertion =
              v:
              v.appKustNames == v.publicApps
              &&
                v.appKustNames == [
                  "myapp1"
                  "myapp2"
                ];
          }
          {
            description = "the root Kustomization (source name) is present";
            expression = lib.length rootKust;
            expected = 1;
          }
        ];
      };
    };
in
# Each entry sets the testModule's `module` option (the same shape the `path`
# coercion in modules/testing/default.nix produces), so eval.nix evaluates each
# case module as its own nixidy config.
[
  { module = argocdCase; }
  { module = fluxCase; }
]
