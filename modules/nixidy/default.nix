{ lib, config, ... }:
let
  cfg = config.nixidy;
in
{
  imports = [
    ./defaults.nix
    ./app-of-apps.nix
    ./extra-files.nix
  ];

  options.nixidy = with lib; {
    env = mkOption {
      type = types.str;
      default = "default";
      description = "The environment name for this configuration.";
    };

    appendNameWithEnv = mkOption {
      type = types.bool;
      default = false;
      description = "When this is set to true, all applications names will be suffixed by the environment.";
    };

    target = {
      repository = mkOption {
        type = types.str;
        description = "The repository URL to put in all generated applications.";
      };
      branch = mkOption {
        type = types.str;
        description = "The destination branch of the generated applications.";
      };
      rootPath = mkOption {
        type = types.str;
        default = "./";
        description = "The root path of all generated applications in the repository.";
      };
    };

    build = {
      revision = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = literalExpression ''
          if (self ? rev) then self.rev else self.dirtyRev
        '';
        description = "The revision being built. Will be written to `.revision` in the environment destination directory.";
      };
    };

    charts = mkOption {
      type = with types; attrsOf anything;
      default = { };
      description = "Attrset of derivations containing helm charts. This will be passed as `charts` to every module.";
    };
    chartsDir = mkOption {
      type = with types; nullOr path;
      default = null;
      description = "Path to a directory containing sub-directory structure that can be used to build a charts attrset. This will be passed as `charts` to every module.";
    };

    assertions = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            assertion = mkOption {
              type = types.bool;
              description = "Whether the assertion holds.";
            };
            message = mkOption {
              type = types.str;
              description = "Message to display if assertion fails.";
            };
          };
        }
      );
      default = [ ];
      # Add context field to assertions
      apply = map (a: {
        inherit (a) assertion message;
        context = "global";
      });
      description = ''
        List of global assertions that must hold during build time. If any assertion is false,
        the build will fail with the corresponding message.

        These assertions are evaluated alongside per-application assertions.
      '';
    };

    warnings = mkOption {
      type = types.listOf (
        types.coercedTo (types.str)
          (x: {
            when = true;
            message = x;
          })
          (
            types.submodule {
              options = {
                when = mkOption {
                  type = types.bool;
                  default = false;
                };
                message = mkOption {
                  type = types.str;
                };
              };
            }
          )
      );
      default = [ ];
      # Add context field to warnings
      apply = map (warning: {
        inherit (warning) when message;
        context = "global";
      });
      description = ''
        List of warnings that will be printed during build time when `when` is `true`, but will not fail the build.
      '';
    };

    publicApps = mkOption {
      type = with types; listOf str;
      default = [ ];
      internal = true;
      description = ''
        List of the names of all applications that do not contain the internal `__` prefix.
      '';
    };
  };

  config = {
    _module.args.charts = config.nixidy.charts;

    nixidy = {
      charts = lib.optionalAttrs (cfg.chartsDir != null) (lib.helm.mkChartAttrs cfg.chartsDir);

      extraFiles = lib.optionalAttrs (cfg.build.revision != null) {
        ".revision".text = cfg.build.revision;
      };

      publicApps = builtins.filter (n: !(lib.hasPrefix "__" n)) (builtins.attrNames config.applications);
    };
  };
}
