{
  testing = {
    name = "nixidy modules";

    tests = [
      ./defaults.nix
      ./sync-options.nix
      ./compare-options.nix
      ./create-namespace.nix
      ./yamls.nix
      ./override-name.nix
      ./internal-apps.nix
      ./no-port-protocol.nix
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
