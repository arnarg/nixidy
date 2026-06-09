{
  lib,
  config,
  ...
}:
let
  renders = config.build._fileRenders.test1;
  paths = lib.attrNames renders;
  hasSuffix = suf: lib.any (p: lib.hasSuffix suf p) paths;
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
      # Eval-time map: Secret -> SopsSecret (so render sees the rewritten kind).
      match.kind = "Secret";
      map =
        s:
        s
        // {
          kind = "SopsSecret";
          apiVersion = "isindir.github.com/v1alpha3";
        };
    }
    {
      # Runtime render attached to the rewritten resource's output file.
      match.kind = "SopsSecret";
      render.command = "cat";
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
    description = "render rules key the post-map SopsSecret output file (sanitized dotted name) and skip non-matched resources";
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
        expression = renders;
        assertion =
          r:
          let
            key = lib.head (lib.filter (p: lib.hasSuffix "SopsSecret-x-y.yaml" p) (lib.attrNames r));
          in
          lib.isList r.${key}.rules && r.${key}.rules != [ ] && r.${key}.resource.kind == "SopsSecret";
      }
      {
        description = "a function-form render command resolves against the matched resource and path";
        expression = renders;
        assertion =
          r:
          let
            key = lib.head (lib.filter (p: lib.hasSuffix "SopsSecret-x-y.yaml" p) (lib.attrNames r));
            entry = r.${key};
            fnRule = lib.head (lib.filter (rule: lib.isFunction rule.render.command) entry.rules);
            resolved = fnRule.render.command {
              resource = entry.resource;
              path = key;
              pkgs = { };
              inherit lib;
            };
          in
          lib.hasInfix "ns=test" resolved && lib.hasInfix "path=${key}" resolved;
      }
    ];
  };
}
