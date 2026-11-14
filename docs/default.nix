{
  pkgs ? null,
  system ? builtins.currentSystem,
  # Path to nixtml's source, defaults to the version pinned with npins.
  nixtml ? null,
}:
let
  # Get some sources from npins.
  sources = import ./npins;
  npkgs = if pkgs == null then import sources.nixpkgs { inherit system; } else pkgs;
  nixtmlSrc = if nixtml == null then sources.nixtml else nixtml;

  # Some inputs from the root flake need
  # be available to the docs generation.
  # To make sure they are the same version
  # as is used by the flake I read the flake.lock
  # and fetch them below.
  flakeLock = builtins.fromJSON (builtins.readFile ../flake.lock);
  kubelib =
    let
      lock = flakeLock.nodes.nix-kube-generators.locked;
    in
    npkgs.fetchFromGitHub {
      inherit (lock) owner repo rev;
      hash = lock.narHash;
    };
in
# Build docs!
import ./docs.nix {
  pkgs = npkgs;
  nixtml = {
    lib = import "${nixtmlSrc}/lib.nix";
    themes.docs = import "${nixtmlSrc}/themes/docs";
  };
  lib = import ../lib {
    inherit kubelib;
    pkgs = npkgs;
  };
}
