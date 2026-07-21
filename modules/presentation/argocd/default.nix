{ lib, config, ... }:
let
  cfg = config.nixidy;
  argocdDefaults = cfg.presentation.argocd.defaults;

  # Back-compat aliases: value-forward the old top-level paths to their new homes
  # under `nixidy.presentation.argocd.*`. The top-level module declares a
  # `warnings` option, so these renames surface a deprecation warning.
  topAliases =
    (map
      (
        path:
        lib.mkRenamedOptionModule
          (
            [
              "nixidy"
              "appOfApps"
            ]
            ++ path
          )
          (
            [
              "nixidy"
              "presentation"
              "argocd"
            ]
            ++ path
          )
      )
      [
        [ "name" ]
        [ "namespace" ]
        [ "project" ]
        [
          "destination"
          "name"
        ]
        [
          "destination"
          "server"
        ]
      ]
    )
    ++ (map
      (
        path:
        lib.mkRenamedOptionModule
          (
            [
              "nixidy"
              "defaults"
            ]
            ++ path
          )
          (
            [
              "nixidy"
              "presentation"
              "argocd"
              "defaults"
            ]
            ++ path
          )
      )
      [
        [ "finalizer" ]
        [
          "syncPolicy"
          "autoSync"
          "enable"
        ]
        [
          "syncPolicy"
          "autoSync"
          "prune"
        ]
        [
          "syncPolicy"
          "autoSync"
          "selfHeal"
        ]
        [
          "destination"
          "name"
        ]
        [
          "destination"
          "server"
        ]
      ]
    );
in
{
  # The top-level back-compat aliases. `present.nix` is imported as a pure
  # function by the registry entry below (not as a module), so it is absent here.
  imports = topAliases;

  # Top-level argocd config: the app-of-apps target (the old `nixidy.appOfApps.*`)
  # and the per-application argocd defaults (the old argocd entries of
  # `nixidy.defaults.*`). Declared unconditionally so the top-level aliases always
  # have a target; read by the argocd synthesis (present.nix) via the registry.
  options.nixidy.presentation.argocd = with lib; {
    name = mkOption {
      type = types.str;
      default = "apps";
      description = "Name of the application for bootstrapping all other applications (app of apps pattern).";
    };
    namespace = mkOption {
      type = types.str;
      default = "argocd";
      description = "Destination namespace for generated Argo CD Applications in the app of apps applications.";
    };
    project = mkOption {
      type = types.str;
      default = "default";
      description = "The project of the generated bootstrap app for appOfApps";
    };
    destination = {
      name = mkOption {
        type = types.nullOr types.str;
        default = argocdDefaults.destination.name;
        defaultText = literalExpression "config.nixidy.presentation.argocd.defaults.destination.name";
        description = ''
          The name of the cluster that ArgoCD should deploy the app of apps to.
        '';
      };
      server = mkOption {
        type = types.nullOr types.str;
        default = argocdDefaults.destination.server;
        defaultText = literalExpression "config.nixidy.presentation.argocd.defaults.destination.server";
        description = ''
          The Kubernetes server that ArgoCD should deploy the app of apps to.
        '';
      };
    };

    defaults = {
      finalizer = mkOption {
        type = types.enum [
          "background"
          "foreground"
          "non-cascading"
        ];
        default = "non-cascading";
        description = ''
          Specify the default finalizer to apply to all ArgoCD application, by default.
        '';
      };

      syncPolicy = {
        autoSync = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if applications should automatically sync.

              This is the default value for all applications if not explicitly set for the application.
            '';
          };
          prune = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if resources should be pruned during auto-syncing.

              This is the default value for all applications if not explicitly set for the application.
            '';
          };
          selfHeal = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Specifies if partial app sync should be executed when resources are changed only in
              target Kubernetes cluster and no git change detected.

              This is the default value for all applications if not explicitly set for the application.
            '';
          };
        };
      };

      destination = {
        name = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            The name of the cluster that ArgoCD should deploy all applications to.

            This is the default value for all applications if not explicitly set for the application.
          '';
        };
        server = mkOption {
          type = types.nullOr types.str;
          default = "https://kubernetes.default.svc";
          description = ''
            The Kubernetes server that ArgoCD should deploy all applications to.

            This is the default value for all applications if not explicitly set for the application.
          '';
        };
      };
    };
  };

  # Register the ArgoCD backend unconditionally. The dispatcher
  # (../default.nix) threads this record into the config only when
  # `nixidy.presentation.backend == "argocd"`, so a flux-only config pulls in
  # neither the `Application` CRD type nor the per-app argocd options.
  config.nixidy.presentation.backends.argocd = {
    # Per-application argocd options (`applications.<name>.argocd.*`) plus the
    # back-compat aliases for the old top-level paths.
    perAppOptions = [
      ./options.nix
      ./aliases.nix
    ];

    # The ArgoCD `Application` CRD type.
    typeImports = [ ../../generated/argocd.nix ];

    # `present` is pure over `ctx`; it additionally closes over the backend-local
    # `nixidy.presentation.argocd.*` config (spliced into ctx here), which is
    # argocd-specific and deliberately kept out of the shared ctx.
    present = ctx: import ./present.nix (ctx // { argocd = config.nixidy.presentation.argocd; });

    # The argocd backend owns the bootstrap manifest filename: the `__bootstrap`
    # app renders exactly one object — the app-of-apps `Application` — and
    # `build/` names each rendered file `<Kind>-<name>.yaml` via `objectBaseName`.
    # extra-files.nix reads this generic seam instead of hardcoding `Application-`.
    # The app-of-apps app's name is never env-suffixed (mkApplication suffixes
    # only when `app.name != argocd.name`), so this filename is stable.
    bootstrapFile = "${
      (import ../../applications/lib.nix lib).objectBaseName {
        kind = "Application";
        metadata.name = config.nixidy.presentation.argocd.name;
      }
    }.yaml";
  };
}
