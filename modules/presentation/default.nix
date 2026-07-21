# Presentation dispatch: resolve the selected backend from the `backends`
# registry and thread its pure record into the config that drives synthesis.
#
# A backend is a pure record `{ perAppOptions; typeImports; present; bootstrapFile; }`.
# `present :: ctx -> attrsOf appConfig` synthesizes the controller objects (ArgoCD
# `Application`s, Flux `Kustomization`s) from a read-only `ctx` — no module `config`
# access, no `mkIf (backend == ...)` guards. Adding a backend is adding a registry
# entry.
{
  lib,
  config,
  ...
}:
let
  cfg = config.nixidy;
  known = cfg.presentation.backends ? ${cfg.presentation.backend};
  sel = if known then cfg.presentation.backends.${cfg.presentation.backend} else { };

  # The read-only synthesis context handed to a backend's `present`: the target
  # coordinates, env/naming policy, and the resolved applications. Everything a
  # backend needs to build its controller objects, and nothing that would let it
  # read back its own output.
  ctx = {
    target = { inherit (cfg.target) repository branch rootPath; };
    inherit (cfg) env appendNameWithEnv publicApps;
    apps = config.applications;
    inherit lib;
  };
in
{
  imports = [
    ./argocd
    ./flux
  ];

  options.nixidy.presentation = with lib; {
    backend = mkOption {
      type = types.str;
      default = "argocd";
      description = "The GitOps presentation backend key (see `nixidy.presentation.backends`).";
    };

    backends = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            perAppOptions = mkOption {
              type = with types; listOf raw;
              default = [ ];
              description = "Modules contributing per-application options (`applications.<name>.<key>.*`).";
            };
            typeImports = mkOption {
              type = with types; listOf raw;
              default = [ ];
              description = "Modules registering the resource types this backend emits (fed to `nixidy.applicationImports`).";
            };
            present = mkOption {
              type = with types; functionTo raw;
              default = _: { };
              description = "Pure synthesis `ctx -> app-config`; its result is contributed to the `applications` option.";
            };
            bootstrapFile = mkOption {
              type = with types; nullOr str;
              default = null;
              description = "Filename of the rendered bootstrap manifest, or `null`.";
            };
          };
        }
      );
      default = { };
      description = ''
        Registry of presentation backends. The built-ins register `argocd` and
        `flux`; add an entry to provide your own.
      '';
    };

    perAppModules = mkOption {
      # `raw` (not `applicationImports`' precise oneOf): a backend may contribute
      # any module value (inline attrset, function, alias module), all of which
      # are spliced verbatim into the applications submodule's `modules` list.
      type = with types; listOf raw;
      default = [ ];
      internal = true;
      description = "Per-application option modules contributed by the active presentation backend (threaded into the applications submodule).";
    };
    bootstrapManifestFile = mkOption {
      type = with types; nullOr str;
      default = null;
      internal = true;
      description = ''
        Filename (within `build.bootstrapPackage`) of the rendered bootstrap
        manifest, set by the active presentation backend. Consumed by
        `nixidy.bootstrapManifest.enable` to emit `bootstrap.yaml`.
      '';
    };
  };

  config = {
    nixidy = {
      assertions = [
        {
          assertion = known;
          message =
            "unknown presentation backend `${cfg.presentation.backend}`; "
            + "known backends: ${lib.concatStringsSep ", " (lib.attrNames cfg.presentation.backends)}.";
        }
      ];

      applicationImports = lib.mkIf cfg.baseImports (sel.typeImports or [ ]);

      presentation = {
        perAppModules = sel.perAppOptions or [ ];
        bootstrapManifestFile = sel.bootstrapFile or null;
      };
    };

    applications = (sel.present or (_: { })) ctx;
  };
}
