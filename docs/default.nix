let
  # Get some sources from npins.
  sources = import ./npins;
  pkgs = import sources.nixpkgs {};

  # Some inputs from the root flake need
  # be available to the docs generation.
  # To make sure they are the same version
  # as is used by the flake I read the flake.lock
  # and fetch them below.
  flakeLock = builtins.fromJSON (builtins.readFile ../flake.lock);
  kubenix = let
    lock = flakeLock.nodes.kubenix.locked;
  in
    pkgs.fetchFromGitHub {
      inherit (lock) owner repo rev;
      hash = lock.narHash;
    };
  kubelib = let
    lock = flakeLock.nodes.nix-kube-generators.locked;
  in
    pkgs.fetchFromGitHub {
      inherit (lock) owner repo rev;
      hash = lock.narHash;
    };

  # Setup nuschtos without using a flake.
  nuschtos = sources.search;
  ixx = sources.ixx;
  ixxPkgs = {
    ixx = pkgs.callPackage "${ixx}/ixx/derivation.nix" {};
    fixx = pkgs.callPackage "${ixx}/fixx/derivation.nix" {};
    libixx = pkgs.callPackage "${ixx}/libixx/derivation.nix" {};
  };
  nuscht-search = pkgs.callPackage "${nuschtos}/nix/frontend.nix" {};
  mkSearch = (pkgs.callPackage "${nuschtos}/nix/wrapper.nix" {inherit nuscht-search ixxPkgs;}).mkSearch;
in
  # Build docs!
  import ./docs.nix {
    inherit pkgs kubenix mkSearch;
    lib = import ../lib {
      inherit pkgs kubelib;
    };
  }
