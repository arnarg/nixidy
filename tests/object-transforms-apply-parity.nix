{
  lib,
  config,
  ...
}:
let
  rawYaml = ./extra-raw-yamls/encrypted-secret.yaml;
  rawYamlName = baseNameOf rawYaml;

  applyFiles = config.build._applyFiles;

  # The post-rewrite SopsSecret entry (sanitized dotted name x.y -> x-y).
  sopsEntry = lib.head (lib.filter (e: lib.hasSuffix "SopsSecret-x-y.yaml" e.path) applyFiles);
in
{
  applications.test1 = {
    namespace = "test";
    # Dotted name exercises the sanitize (dot -> dash) path key.
    resources.secrets."x.y".stringData.x = "y";
    resources.configMaps.cm.data.FOO = "bar";
  };

  applications.test2 = {
    namespace = "test";
    resources.configMaps.cm2.data.BAR = "baz";
    # Raw yaml is copied verbatim by mkApp; it has no parsed object and so must
    # not appear in applyFiles.
    extraRawYamls = [ rawYaml ];
  };

  nixidy.objectTransforms = [
    {
      # Eval-time rewrite: Secret -> SopsSecret (so postProcess sees the new kind).
      name = "secret-to-sopssecret";
      match.kind = "Secret";
      rewrite =
        s:
        s
        // {
          kind = "SopsSecret";
          apiVersion = "isindir.github.com/v1alpha3";
        };
    }
    {
      # Function-form command: resolved at eval time against the matched object.
      match.kind = "SopsSecret";
      postProcess.command =
        {
          resource,
          ...
        }:
        "cat # ns=${resource.metadata.namespace}";
    }
  ];

  test = {
    name = "objectTransforms apply parity";
    description = "applyFiles enumerates environmentPackage resource files (excluding appOfApps, __-apps, raw yamls) and function-form postProcess commands resolve identically on the apply and switch paths";
    assertions = [
      {
        description = "applyFiles excludes the appOfApps app and any __-prefixed app";
        expression = applyFiles;
        assertion =
          fs: !(lib.any (e: e.app == config.nixidy.appOfApps.name || lib.hasPrefix "__" e.app) fs);
      }
      {
        description = "the SopsSecret entry exists with class manifests, non-empty rules, and sanitized dotted path";
        expression = sopsEntry;
        assertion =
          e: e.class == "manifests" && e.rules != [ ] && lib.hasSuffix "SopsSecret-x-y.yaml" e.path;
      }
      {
        description = "no applyFiles entry references the extraRawYamls filename";
        expression = applyFiles;
        assertion = fs: !(lib.any (e: lib.hasInfix rawYamlName e.path) fs);
      }
      {
        description = "function-form postProcess command resolves against the apply entry's resource/path identically to the switch path";
        expression = sopsEntry;
        assertion =
          e:
          let
            resolved = (builtins.head e.rules).postProcess.command {
              resource = e.resource;
              path = e.path;
              pkgs = { };
              inherit lib;
            };
          in
          lib.hasInfix "ns=test" resolved;
      }
    ];
  };
}
