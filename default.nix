{nixpkgs ? null}: let
  flakeLock = builtins.fromJSON (builtins.readFile ./flake.lock);

  flakeLockMeta = node: let
    lock = flakeLock.nodes.${node}.locked;
  in {
    inherit (lock) owner repo rev type;
    hash = lock.narHash;
  };

  npkgs = let
    meta = flakeLockMeta "nixpkgs";

    source =
      if nixpkgs == null
      then
        builtins.fetchTarball {
          url = "https://github.com/${meta.owner}/${meta.repo}/archive/${meta.rev}.tar.gz";
          sha256 = meta.hash;
        }
      else nixpkgs;
  in
    import source {};

  importFromFlakeLock = node: let
    lock = flakeLockMeta node;
  in
    if lock.type == "github"
    then npkgs.fetchFromGitHub (removeAttrs lock ["type"])
    else throw "fetcher for type ${lock.type} unsupported";

  kubenix = importFromFlakeLock "kubenix";
  kubelib = importFromFlakeLock "nix-kube-generators";

  lib = import ./make-env.nix {inherit kubenix kubelib;};
in {
  lib = {
    mkEnv = args @ {pkgs ? npkgs, ...}: lib.mkEnv (args // {inherit pkgs;});
    mkEnvs = args @ {pkgs ? npkgs, ...}: lib.mkEnvs (args // {inherit pkgs;});
  };
}
