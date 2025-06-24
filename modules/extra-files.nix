{
  lib,
  pkgs,
  config,
  ...
}: {
  options.nixidy = with lib; {
    extraFiles = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        options,
        ...
      }: {
        options = {
          path = mkOption {
            type = types.str;
            default = name;
            description = "Path of output file.";
          };
          text = mkOption {
            type = with types; nullOr lines;
            default = null;
            description = "Text of the output file.";
          };
          source = mkOption {
            type = types.path;
            description = "Path of the source file.";
          };
        };

        config = {
          source = lib.mkIf (config.text != null) (
            let
              name' = "nixidy-" + lib.replaceStrings ["/"] ["-"] name;
            in
              lib.mkDerivedConfig options.text (pkgs.writeText name')
          );
        };
      }));
      default = {};
      description = ''
        Extra files to write in the generated stage.
      '';
    };

    bootstrapManifest.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically include a `bootstrap.yaml` manifest in the generated output. This can be used to bootstrap the app of apps by running `kubectl apply -f bootstrap.yaml`.
      '';
    };
  };

  config = lib.mkIf config.nixidy.bootstrapManifest.enable {
    nixidy.extraFiles."bootstrap.yaml".source = "${config.build.bootstrapPackage}/Application-${config.nixidy.appOfApps.name}.yaml";
  };
}
