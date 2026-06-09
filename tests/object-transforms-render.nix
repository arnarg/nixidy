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
        description = "the SopsSecret render entry is a non-empty list of rules";
        expression = renders;
        assertion =
          r:
          let
            key = lib.head (lib.filter (p: lib.hasSuffix "SopsSecret-x-y.yaml" p) (lib.attrNames r));
          in
          lib.isList r.${key} && r.${key} != [ ];
      }
    ];
  };
}
