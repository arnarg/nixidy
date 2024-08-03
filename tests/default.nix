{
  testing = {
    name = "nixidy modules";

    tests = [
      ./defaults.nix
      ./sync-options.nix
      ./compare-options.nix
      ./create-namespace.nix
      ./yamls.nix
      ./helm
    ];
  };
}
