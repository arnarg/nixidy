{
  lib,
  config,
  ...
}:
let
  objs = config.build._transformedObjects.test1;
in
{
  applications.test1 = {
    namespace = "test";
    resources.secrets."a-b".stringData.x = "y";
    resources.configMaps.cm.data.FOO = "bar";
    objectTransforms = [
      {
        match.kind = "SopsSecret";
        map =
          o:
          o
          // {
            metadata = (o.metadata or { }) // {
              annotations = (o.metadata.annotations or { }) // {
                "ordering-proof" = "app-ran-after-env";
              };
            };
          };
      }
    ];
  };

  nixidy.objectTransforms = [
    {
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
      match.kind = "ConfigMap";
      map = _: null;
    }
  ];

  test = {
    name = "objectTransforms map";
    description = "eval-time map rewrites Secret -> SopsSecret and drops ConfigMap via map -> null";
    assertions = [
      {
        description = "Secret was rewritten to SopsSecret";
        expression = objs;
        assertion = os: lib.any (o: o.kind == "SopsSecret") os;
      }
      {
        description = "ConfigMap was dropped (map -> null)";
        expression = objs;
        assertion = os: lib.length (lib.filter (o: o.kind == "ConfigMap") os) == 0;
      }
      {
        description = "rewritten SopsSecret retains its metadata.name";
        expression = lib.head (lib.filter (o: o.kind == "SopsSecret") objs);
        assertion = o: o.metadata.name == "a-b";
      }
      {
        description = "env rules apply before app rules";
        expression = objs;
        assertion = os: lib.any (o: (o.metadata.annotations or { }) ? "ordering-proof") os;
      }
    ];
  };
}
