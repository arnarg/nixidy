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
    testing.success = lib.all (test: test.success) config.testing.tests;

    testing.report =
      lib.concatMapStringsSep "\n" (
        test: let
          result =
            if test.success
            then "\\033[1;32mPASS\\033[0m"
            else "\\033[1;31mFAIL\\033[0m";
        in
          "[${result}] ${test.name}"
          + (
            lib.optionalString (!test.success)
            "\n${test.report}"
          )
      )
      config.testing.tests;

    testing.reportScript = pkgs.writeShellScript "testing-${config.testing.name}-report-script" ''
      set -eo pipefail

      printf '${config.testing.report}'

      exit ${
        if config.testing.success
        then "0"
        else "1"
      }
    '';
  };
}
