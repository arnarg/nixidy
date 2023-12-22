{
  modules,
  pkgs,
  kubelib,
  lib ? pkgs.lib,
  extraSpecialArgs ? {},
}: let
  extendedLib = import ../lib {inherit pkgs kubelib;};

  nixidyModules = import ./modules.nix;

  module = lib.evalModules {
    modules = modules ++ nixidyModules;
    specialArgs =
      {
        inherit pkgs;
        lib = extendedLib;
      }
      // extraSpecialArgs;
  };
in {
  meta = {
    repository = module.config.nixidy.target.repository;
    branch = module.config.nixidy.target.branch;
  };
  environmentPackage = module.config.nixidy.environmentPackage;
}
