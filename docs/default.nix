{pkgs ? null}: let
  # Get some sources from npins.
  sources = import ./npins;
  npkgs =
    if pkgs == null
    then import sources.nixpkgs {}
    else pkgs;

  # Some inputs from the root flake need
  # be available to the docs generation.
  # To make sure they are the same version
  # as is used by the flake I read the flake.lock
  # and fetch them below.
  flakeLock = builtins.fromJSON (builtins.readFile ../flake.lock);
  kubelib = let
    lock = flakeLock.nodes.nix-kube-generators.locked;
  in
    npkgs.fetchFromGitHub {
      inherit (lock) owner repo rev;
      hash = lock.narHash;
    };

  # Setup nuschtos without using a flake.
  nuschtos = sources.search;
  ixx = sources.ixx;
  ixxPkgs = {
    ixx = npkgs.callPackage "${ixx}/ixx/derivation.nix" {};
    fixx = npkgs.callPackage "${ixx}/fixx/derivation.nix" {};
    libixx = npkgs.callPackage "${ixx}/libixx/derivation.nix" {};
  };
  nuscht-search = npkgs.callPackage "${nuschtos}/nix/frontend.nix" {};
  mkSearch = (npkgs.callPackage "${nuschtos}/nix/wrapper.nix" {inherit nuscht-search ixxPkgs;}).mkSearch;
in
  # Build docs!
  import ./docs.nix {
    inherit mkSearch;
    pkgs = npkgs;
    lib = import ../lib {
      inherit kubelib;
      pkgs = npkgs;
    };
  }
