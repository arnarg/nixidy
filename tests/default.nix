{
  testing = {
    name = "nixidy modules";

    tests = [
      ./defaults.nix
      ./sync-options.nix
      ./compare-options.nix
    ];
  };
}
