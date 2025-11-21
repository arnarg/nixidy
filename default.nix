{
  nixpkgs ? null,
}:
let
  # To not having to maintain versions of dependencies in 2 locations
  # we here read the flake.lock to parse revisions and hashes
  # for a select few dependencies.
  flakeLock = builtins.fromJSON (builtins.readFile ./flake.lock);

  # Helper function to fetch metadata about a locked input.
  # Currently only fetches relevant information for github.
  flakeLockMeta =
    node:
    let
      lock = flakeLock.nodes.${node}.locked;
    in
    {
      inherit (lock)
        owner
        repo
        rev
        type
        ;
      hash = lock.narHash;
    };

  # Import nixpkgs from either parameter or the lock file.
  pkgs =
    let
      meta = flakeLockMeta "nixpkgs";
      npkgs =
        if nixpkgs == null then
          builtins.fetchTarball {
            url = "https://github.com/${meta.owner}/${meta.repo}/archive/${meta.rev}.tar.gz";
            sha256 = meta.hash;
          }
        else
          nixpkgs;
    in
    import npkgs { };

  # Helper function that can fetch input from flake.lock
  # by its name.
  fetchFromFlakeLock =
    node:
    let
      lock = flakeLockMeta node;
    in
    if lock.type == "github" then
      pkgs.fetchFromGitHub (removeAttrs lock [ "type" ])
    else
      throw "fetcher for type ${lock.type} unsupported";

  # Get nix-kube-generators.
  kubelib =
    let
      src = fetchFromFlakeLock "nix-kube-generators";
    in
    {
      lib = import "${src}/lib";
    };

  # Import the lib functions present in the flake.
  lib = import ./make-env.nix { inherit kubelib; };

  # Import the generator functions present in the flake.
  generators = import ./pkgs/generators { inherit pkgs kubelib; };
in
{
  # Wrap the lib functions to use the pkgs imported above
  # without having the user needing to pass it in.
  lib = {
    mkEnv = args: lib.mkEnv ({ inherit pkgs; } // args);
    mkEnvs = args: lib.mkEnvs ({ inherit pkgs; } // args);
  };

  # Have the nixidy cli available.
  nixidy = pkgs.callPackage ./nixidy/nixidy.nix { };

  # Have generators available.
  generators = { inherit (generators) fromCRD fromChartCRD; };
}
