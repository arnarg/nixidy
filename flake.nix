{
  description = "ArgoCD application and Kubernetes manifest generator in Nix.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix-kube-generators.url = "github:farcaller/nix-kube-generators";

  inputs.kubenix = {
    url = "github:hall/kubenix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nix-kube-generators,
    kubenix,
  }:
    {
      lib = rec {
        mkEnv = {
          pkgs,
          lib ? pkgs.lib,
          modules ? [],
          extraSpecialArgs ? {},
          charts ? {},
        }:
          import ./modules {
            inherit pkgs lib extraSpecialArgs kubenix;
            kubelib = nix-kube-generators;
            modules =
              modules
              ++ [
                {
                  nixidy.charts = charts;
                }
              ];
          };

        mkEnvs = {
          pkgs,
          lib ? pkgs.lib,
          modules ? [],
          extraSpecialArgs ? {},
          envs ? {},
          charts ? {},
        }:
          lib.mapAttrs (
            env: conf:
              mkEnv {
                inherit pkgs lib charts;
                extraSpecialArgs = extraSpecialArgs // (conf.extraSpecialArgs or {});
                modules =
                  [{nixidy.target.rootPath = lib.mkDefault "./manifests/${env}";}]
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
        generators = import ./pkgs/generators {inherit pkgs;};
      };

      apps = {
        # Generates all generators and copies into place
        generate = {
          type = "app";
          program = with pkgs.lib;
            (pkgs.writeShellScript "generate-modules" ''
              set -eo pipefail
              dest=./modules/generated

              ${concatStringsSep "\n" (mapAttrsToList (
                n: mod: ''
                  echo "generating ${n}"
                  cat ${mod} > $dest/${n}.nix
                ''
              ) (removeAttrs self.packages.${system}.generators ["fromCRD"]))}

              echo "done!"
            '')
            .outPath;
        };
      };
    }));
}
