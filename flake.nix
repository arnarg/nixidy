{
  description = "ArgoCD application and Kubernetes manifest generator in Nix.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-kube-generators.url = "github:farcaller/nix-kube-generators";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nix-kube-generators,
  }:
    {
      lib = import ./make-env.nix {
        kubelib = nix-kube-generators;
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
        generate = let
          generated = pkgs.linkFarm "generated-modules" [
            {
              name = "argocd.nix";
              path = self.packages.${system}.generators.argocd;
            }
            {
              name = "k8s";
              path = self.packages.${system}.generators.k8s;
            }
          ];
        in {
          type = "app";
          program =
            (pkgs.writeShellScript "generate-modules" ''
              set -eo pipefail
              dest=./modules/generated

              echo "generating modules..."
              ${pkgs.rsync}/bin/rsync \
                --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r \
                --copy-links --recursive --delete \
                "${generated}/" "$dest"

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

        # Run shellcheck on nixidy cli
        cliTest = {
          type = "app";
          program =
            (pkgs.writeShellScript "cli-shellcheck-test" ''
              ${pkgs.shellcheck}/bin/shellcheck ${self.packages.${system}.default}/bin/nixidy
            '')
            .outPath;
        };

        # Run tests for crd2jsonschema
        crd2jsonschemaTest = {
          type = "app";
          program = let
            pythonWithYaml = pkgs.python3.withPackages (ps: [ps.pyyaml]);
          in
            (pkgs.writeShellScript "crd2jsonschema-test" ''
              ${pythonWithYaml}/bin/python ${self}/pkgs/generators/crd/test_crd2jsonschema.py
            '').outPath;
        };

        # Serve docs
        docsServe = {
          type = "app";
          program =
            (pkgs.writeShellScript "serve-docs" ''
              ${pkgs.python3}/bin/python -m http.server -d ${(import ./docs {inherit pkgs;}).html} 8080
            '')
            .outPath;
        };
      };
    }));
}
