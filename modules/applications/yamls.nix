{
  lib,
  config,
  ...
}:
let
  helpers = import ./lib.nix lib;
in
{
  options = with lib; {
    yamls = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: default
        ''
      ];
      description = ''
        List of Kubernetes manifests declared in YAML strings. They will be parsed and added to the application's
        `resources` where they can be overwritten and modified.

        Can be useful for reading existing YAML files (i.e. `[(builtins.readFile ./deployment.yaml)]`).
      '';
    };

    extraRawYamls = mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = literalExpression ''
        [ ./encrypted-secret.yaml ]
      '';
      description = ''
        List of YAML files to include in the application's output directory.
        Each file's basename becomes the output filename.

        Unlike `yamls`, the content is **not** parsed into Nix and therefore cannot be patched through
        `resources`. This is intended for files that contain fields incompatible with the typed schema;
        most notably [SOPS](https://github.com/getsops/sops)-encrypted manifests, which carry a top-level
        `sops` metadata block that would otherwise be stripped or altered by a parse/emit round-trip.
      '';
    };
  };

  config =
    with lib;
    let
      partitioned = helpers.partitionObjects config.types (concatMap kube.fromYAML config.yamls);

      rawBasenames = map baseNameOf config.extraRawYamls;
      duplicateRawBasenames = unique (filter (n: count (m: m == n) rawBasenames > 1) rawBasenames);

      typedFilename = obj: "${helpers.objectBaseName obj}.yaml";
      typedFilenames = map typedFilename config.objects;
      typedCollisions = filter (n: elem n typedFilenames) (unique rawBasenames);
    in
    {
      inherit (partitioned) objects resources;

      assertions = optionals (config.extraRawYamls != [ ]) [
        {
          assertion = duplicateRawBasenames == [ ];
          message =
            "extraRawYamls entries share basename(s): "
            + concatStringsSep ", " (
              map (
                n:
                "${n} (from: ${
                  concatStringsSep ", " (map toString (filter (p: baseNameOf p == n) config.extraRawYamls))
                })"
              ) duplicateRawBasenames
            )
            + ". Each file in extraRawYamls must have a unique basename.";
        }
        {
          assertion = typedCollisions == [ ];
          message =
            "extraRawYamls basename(s) collide with typed-resource output filenames: "
            + concatStringsSep ", " typedCollisions
            + ". Rename the raw file(s) to avoid overwriting typed manifests.";
        }
      ];
    };
}
