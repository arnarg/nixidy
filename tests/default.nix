{
  testing = {
    name = "nixidy modules";

    tests = [
      ./appOfApps-default-destination.nix
      ./appOfApps-custom-default-destination.nix
      ./appOfApps-custom-appOfApps-destination.nix
      ./defaults.nix
      ./destination.nix
      ./sync-options.nix
      ./compare-options.nix
      ./configmap.nix
      ./create-namespace.nix
      ./limits.nix
      ./yamls.nix
      ./override-name.nix
      ./internal-apps.nix
      ./no-port-protocol.nix
      ./no-suffix-env-to-app-name.nix
      ./suffix-env-to-app-name.nix
      ./templates.nix
      ./helm/no-values.nix
      ./helm/with-values.nix
      ./helm/transformer.nix
      ./helm/resource-override.nix
      ./helm/extra-opts.nix
      ./helm/flatten-lists.nix
      ./kustomize/base.nix
      ./kustomize/overlay.nix
      ./kustomize/resource-override.nix
      ./kustomize/flatten-lists.nix
    ];
  };
}
