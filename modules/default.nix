{
  modules,
  pkgs,
  kubelib,
  kubenix,
  lib ? pkgs.lib,
  extraSpecialArgs ? {},
  libOverlay ? null,
}: let
  extendedLib = import ../lib {inherit pkgs kubelib;};

  nixidyModules = import ./modules.nix;

  module = lib.evalModules {
    modules =
      modules
      ++ nixidyModules
      ++ [
        {
          nixidy.applicationImports = [
            (kubenix + "/modules/generated/v1.30.nix")
            ./generated/argocd.nix
          ];
        }
      ];
    specialArgs =
      {
        inherit pkgs;
        lib =
          if builtins.isFunction libOverlay
          then extendedLib.extend libOverlay
          else extendedLib;
      }
      // extraSpecialArgs;
  };
in {
  inherit (module) config;
  inherit (module.config.build) environmentPackage activationPackage bootstrapPackage;
  meta = {inherit (module.config.nixidy.target) repository branch;};
}
