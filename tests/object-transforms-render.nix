{
  lib,
  config,
  ...
}:
let
  renders = config.build._fileRenders.test1;
  paths = lib.attrNames renders;
  hasSuffix = suf: lib.any (p: lib.hasSuffix suf p) paths;
  # The single rendered SopsSecret entry (post-rewrite, sanitized dotted name).
  sopsKey = lib.head (lib.filter (lib.hasSuffix "SopsSecret-x-y.yaml") paths);
  sopsEntry = renders.${sopsKey};
in
{
  applications.test1 = {
    namespace = "test";
    # Dotted name exercises the sanitize (dot -> dash) path key.
    resources.secrets."x.y".stringData.x = "y";
    resources.configMaps.cm.data.FOO = "bar";
  };

  nixidy.objectTransforms = [
    {
      # Eval-time rewrite: Secret -> SopsSecret (so render sees the new kind).
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
      # String shortcut: coerces to { command = "cat"; runtimeInputs = []; }.
      name = "passthrough";
      match.kind = "SopsSecret";
      render = "cat";
    }
    {
      # Function-form command: resolved at eval time against the matched object.
      match.kind = "SopsSecret";
      render.command =
        {
          resource,
          path,
          ...
        }:
        "cat # ns=${resource.metadata.namespace} path=${path}";
    }
  ];

  test = {
    name = "objectTransforms render";
    description = "render rules key the post-rewrite SopsSecret output file (sanitized dotted name) and skip non-matched resources";
    assertions = [
      {
        description = "fileRenders has a key for the rewritten SopsSecret with sanitized dotted name";
        expression = paths;
        assertion = _: hasSuffix "SopsSecret-x-y.yaml";
      }
      {
        description = "fileRenders has no key for the non-matched ConfigMap";
        expression = paths;
        assertion = _: !(lib.any (p: lib.hasInfix "ConfigMap-" p) paths);
      }
      {
        description = "the SopsSecret render entry carries the matched resource and a non-empty rules list";
        expression = sopsEntry;
        assertion = e: lib.isList e.rules && e.rules != [ ] && e.resource.kind == "SopsSecret";
      }
      {
        description = "the string-form render coerces to { command = \"cat\"; runtimeInputs = []; }";
        expression = sopsEntry;
        assertion =
          e:
          let
            strRule = lib.head (lib.filter (rule: rule.name == "passthrough") e.rules);
          in
          strRule.render.command == "cat" && strRule.render.runtimeInputs == [ ];
      }
      {
        description = "a function-form render command resolves against the matched resource and path";
        expression = sopsEntry;
        assertion =
          e:
          let
            fnRule = lib.head (lib.filter (rule: lib.isFunction rule.render.command) e.rules);
            resolved = fnRule.render.command {
              resource = e.resource;
              path = sopsKey;
              pkgs = { };
              inherit lib;
            };
          in
          lib.hasInfix "ns=test" resolved && lib.hasInfix "path=${sopsKey}" resolved;
      }
    ];
  };
}
