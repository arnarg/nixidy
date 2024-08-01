{
  lib,
  config,
  resourceImports,
  ...
}: let
  testModuleOptions = {
    options.test = with lib; {
      name = mkOption {
        type = types.str;
        description = "Test name.";
      };
      description = mkOption {
        type = types.str;
        description = "Test description.";
      };
      assertions = mkOption {
        type = with types;
          listOf (submodule {
            options = {
              description = mkOption {
                type = str;
                description = "Assertion description.";
              };
              expression = mkOption {
                type = types.anything;
                description = "Expression that should be asserted.";
              };
              assertion = mkOption {
                type = types.functionTo types.bool;
                description = ''
                  Function that should take the value of `expression` as argument and return a bool,
                  depending on if the check passed or not.
                '';
              };
            };
          });
      };
    };
  };

  modules =
    [
      # The module being tested
      config.module

      # Import test module options
      testModuleOptions

      {
        # Import all resourceImports
        nixidy.resourceImports = resourceImports;

        # Set nixidy target
        nixidy.target.repository = "https://github.com/arnarg/nixidy.git";
        nixidy.target.branch = "main";
      }
    ]
    # Import all base nixidy modules
    ++ (import ../modules.nix);

  # Eval without checking
  evaled = lib.evalModules {
    inherit modules;
  };
in {
  options = with lib; {
    module = mkOption {
      type = types.unspecified;
      description = "Module defining the test.";
    };

    success = mkOption {
      type = types.bool;
      default = false;
      description = "Result of the test.";
      internal = true;
    };

    name = mkOption {
      type = types.str;
      description = "test name";
      internal = true;
    };

    description = mkOption {
      type = types.str;
      description = "test description";
      internal = true;
    };

    report = mkOption {
      type = types.str;
      description = "Test report for the assertions.";
      internal = true;
    };
  };

  config = {
    inherit (evaled.config.test) name description;

    success = lib.all (el: el.assertion el.expression) evaled.config.test.assertions;

    report =
      lib.concatMapStringsSep "\n" (
        el: let
          success = el.assertion el.expression;
          result =
            if success
            then "\\033[1;32m✓\\033[0m"
            else "\\033[1;31mx\\033[0m";
        in "       ${result} ${el.description}"
      )
      evaled.config.test.assertions;
  };
}
