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
        # Cross-references the independently-built apply and switch maps: the
        # apply entry's path must be a key in the switch map (`_filePostProcesses`,
        # keyed by `objPath`), and resolving the command from each entry must
        # yield the same string. Guards the parity invariant directly.
        description = "function-form postProcess command resolves identically on the apply and switch paths";
        expression = sopsEntry;
        assertion =
          e:
          let
            switchEntry = config.build._filePostProcesses.${e.app}.${e.path};
            resolve =
              entry:
              (builtins.head entry.rules).postProcess.command {
                resource = entry.resource;
                path = e.path;
                pkgs = { };
                inherit lib;
              };
          in
          resolve e == resolve switchEntry && lib.hasInfix "ns=test" (resolve e);
      }
      {
        # Regression guard on the generated bash itself (the riskiest surface).
        description = "the generated apply script streams to `kubectl apply -f -` per class and emits no glued *.yml";
        expression = config.build._applyScript;
        assertion =
          s:
          lib.hasInfix "set -eo pipefail" s
          && lib.hasInfix "kubectl apply -f -" s
          && lib.hasInfix ''--prune --selector "apps.nixidy.dev/manifests='' s
          && lib.hasInfix "SopsSecret-x-y.yaml" s
          && !(lib.hasInfix "crds.yml" s)
          && !(lib.hasInfix "namespaces.yml" s)
          && !(lib.hasInfix "manifests.yml" s);
      }
    ];
  };
}
