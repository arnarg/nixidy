{
  lib,
  config,
  ...
}: {
  testing = {
    tests = [
      ./defaults.nix
      ./sync-options.nix
    ];
  };
}
