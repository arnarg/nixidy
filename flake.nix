{
  description = "ArgoCD application and Kubernetes manifest generator in Nix.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix-kube-generators.url = "github:farcaller/nix-kube-generators";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nix-kube-generators,
  }:
    {
      lib = rec {
        mkEnv = {
          pkgs,
          lib ? pkgs.lib,
          modules ? [],
          extraSpecialArgs ? {},
        }:
          import ./modules {
            inherit modules pkgs lib extraSpecialArgs;
            kubelib = nix-kube-generators;
          };

        mkEnvs = {
          pkgs,
          lib ? pkgs.lib,
          modules ? [],
          extraSpecialArgs ? {},
          envs ? {},
        }:
          lib.mapAttrs (
            env: conf:
              mkEnv {
                inherit pkgs lib;
                extraSpecialArgs = extraSpecialArgs // (conf.extraSpecialArgs or {});
                modules =
                  [{nixidy.target.branch = lib.mkDefault "env/${env}";}]
                  ++ modules
                  ++ (conf.modules or []);
              }
          )
          envs;
      };
    }
    // (flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };
      docs = import ./docs {
        inherit pkgs;
      };
      packages = import ./nixidy pkgs;
    in {
      packages = {
        default = packages.nixidy;
        docs = docs;
      };
    }));
}
