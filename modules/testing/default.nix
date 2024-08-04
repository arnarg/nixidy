{
  lib,
  config,
  pkgs,
  ...
}: let
  testModule = {
    imports = [./eval.nix];

    _module.args.resourceImports = config.nixidy.resourceImports;
  };
in {
  options.testing = with lib; {
    name = mkOption {
      type = types.str;
      default = "default";
      description = "Testing suite name.";
    };

    tests = mkOption {
      type = with types;
        listOf (
          coercedTo path
          (module: {
            inherit module;
          })
          (submodule testModule)
        );
      default = [];
      description = "List of test cases.";
    };

    testsByName = mkOption {
      description = "Tests by name";
      type = types.attrsOf types.attrs;
      default = listToAttrs (map (test: nameValuePair test.name test) config.testing.tests);
    };

    success = mkOption {
      type = types.bool;
      default = false;
      description = "Result of the entire test suite.";
      internal = true;
    };

    report = mkOption {
      type = types.str;
      description = "Test report for the entire test suite.";
      internal = true;
    };

    reportScript = mkOption {
      type = types.package;
      description = "Script for outputting the report and set exit code.";
      internal = true;
    };
  };

  config = {
    testing = {
      success = lib.all (test: test.success) config.testing.tests;

      report = let
        total = lib.length config.testing.tests;
        passing = lib.count (test: test.success) config.testing.tests;
      in
        (lib.concatMapStringsSep "\n" (
            test: let
              result =
                if test.success
                then "✅"
                else "❌";
            in
              "${result} ${test.name}"
              + (
                lib.optionalString (!test.success)
                "\n${test.report}"
              )
          )
          config.testing.tests)
        + "\n\n${
          if config.testing.success
          then "🎉"
          else "💥"
        } ${toString passing}/${toString total} successful";

      reportScript = pkgs.writeShellScript "testing-${config.testing.name}-report-script" ''
        set -eo pipefail

        printf '${config.testing.report}\n'

        exit ${
          if config.testing.success
          then "0"
          else "1"
        }
      '';
    };
  };
}
