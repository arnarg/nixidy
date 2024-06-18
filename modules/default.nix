{
  modules,
  pkgs,
  kubelib,
  kubenix,
  lib ? pkgs.lib,
  extraSpecialArgs ? {},
}: let
  extendedLib = import ../lib {inherit pkgs kubelib;};

  nixidyModules = import ./modules.nix;

  module = lib.evalModules {
    modules =
      modules
      ++ nixidyModules
      ++ [
        {
          nixidy.resourceImports = [(kubenix + "/modules/generated/v1.30.nix")];
        }
      ];
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
  environmentPackage = module.config.build.environmentPackage;
}
