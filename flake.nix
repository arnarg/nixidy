{
  description = "ArgoCD application and Kubernetes manifest generator in Nix.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-kube-generators.url = "github:farcaller/nix-kube-generators";

    kubenix = {
      url = "github:hall/kubenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
          libOverlay ? null,
        }:
          import ./modules {
            inherit pkgs lib extraSpecialArgs kubenix libOverlay;
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
          libOverlay ? null,
        }:
          lib.mapAttrs (
            env: conf:
              mkEnv {
                inherit pkgs lib charts libOverlay;
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
      packages = import ./nixidy pkgs;
    in {
      packages = {
        default = packages.nixidy;
        generators = import ./pkgs/generators {inherit pkgs;};
      };

      libTests = import ./lib/tests.nix {
        inherit pkgs;
        kubelib = nix-kube-generators;
      };

      moduleTests =
        (self.lib.mkEnv {
          inherit pkgs;
          modules = [
            ./modules/testing
            ./tests
          ];
        })
        .config
        .testing;

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

        # Runs statix for linting the nix code
        staticCheck = {
          type = "app";
          program =
            (pkgs.writeShellScript "static-lint-check" ''
              set -eo pipefail

              # Use a fancy jq filter to turn the JSON output
              # into workflow commands for github actions.
              # See: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-a-warning-message
              if [ "$GITHUB_ACTIONS" = "true" ]; then
                ${pkgs.statix}/bin/statix check -o json . | \
                  ${pkgs.jq}/bin/jq -r '.file as $file |
                    .report | map(
                      .severity as $severity |
                      .note as $note |
                      .diagnostics | map(
                        . + {
                          "file": $file,
                          "note": $note,
                          "severity": (
                            if $severity == "Error"
                            then "error"
                            else "warning"
                            end
                          )
                        }
                      )
                    ) |
                    flatten | .[] |
                    "::\(.severity) file=\(.file),line=\(.at.from.line),col=\(.at.from.column),endLine=\(.at.to.line),endColumn=\(.at.to.column),title=\(.note)::\(.message)"
                  '
              else
                ${pkgs.statix}/bin/statix check .
              fi
            '')
            .outPath;
        };

        # Runs lib unit tests
        libTests = {
          type = "app";
          program =
            (pkgs.writeShellScript "lib-unit-tests" ''
              set -eo pipefail

              SYSTEM=$(nix eval --expr builtins.currentSystem --raw --impure)

              ${pkgs.nix-unit}/bin/nix-unit \
                --extra-experimental-features flakes \
                --flake "${self}#libTests.''${SYSTEM}"
            '')
            .outPath;
        };

        # Run module unit tests
        moduleTests = {
          type = "app";
          program = self.moduleTests.${system}.reportScript.outPath;
        };
      };
    }));
}
