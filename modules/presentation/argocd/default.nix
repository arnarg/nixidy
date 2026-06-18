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
  # The ArgoCD synthesis (app-of-apps + bootstrap synthetic apps) — self-guarded
  # on `backend == "argocd"` — plus the top-level back-compat aliases. `imports`
  # must live outside any `mkIf`.
  imports = [ ./present.nix ] ++ topAliases;

  # Top-level argocd config: the app-of-apps target (the old `nixidy.appOfApps.*`)
  # and the per-application argocd defaults (the old argocd entries of
  # `nixidy.defaults.*`). Declared unconditionally so the top-level aliases always
  # have a target; only read by the argocd synthesis (present.nix), which is
  # itself backend-guarded.
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

  config = lib.mkIf (config.nixidy.presentation.backend == "argocd") {
    # The ArgoCD `Application` CRD type. Conditional on the argocd backend so a
    # flux-only config does not pull it in.
    nixidy.applicationImports = lib.mkIf config.nixidy.baseImports [ ../../generated/argocd.nix ];

    # Per-application argocd options (`applications.<name>.argocd.*`) plus the
    # back-compat aliases for the old top-level paths.
    nixidy.presentation.perAppModules = [
      ./options.nix
      ./aliases.nix
    ];
  };
}
