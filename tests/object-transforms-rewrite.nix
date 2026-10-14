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
    resources = {
      secrets."a-b".stringData.x = "y";
      configMaps.cm.data.FOO = "bar";
      deployments.test = {
        metadata.labels = {
          foo = "foo";
          bar = "bar";
        };
        spec = {
          selector = { };
          template.spec.containers = {
            c1 = { };
            c2.env = {
              a = {
                value = "a";
              };
              b = {
                value = "b";
              };
            };
          };
        };
      };
    };

    objectTransforms = {
      one = {
        match.kind = "SopsSecret";
        update.metadata.annotations.ordering-proof = "app-ran-afer-env";
      };
      two = {
        match.kind = "Deployment";
        transforms.inner = {
          path = [
            "spec"
            "template"
            "spec"
            "containers"
          ];
          update.tty = true;
        };
      };
      three = {
        match.kind = "Deployment";
        transforms.inner = {
          path = [
            "spec"
            "template"
            "spec"
            "containers"
            "env"
          ];
          match.name = "a";
          update.value = "c";
        };
      };
      four = {
        path = [
          "metadata"
          "labels"
          "foo"
        ];
        replace = null;
      };
    };
  };

  nixidy.objectTransforms = {
    one = {
      name = "secret-to-sopssecret";
      match.kind = "Secret";
      update = {
        kind = "SopsSecret";
        apiVersion = "isindir.github.com/v1alpha3";
      };
    };
    two = {
      match.kind = "ConfigMap";
      replace = null;
    };
  };

  test = {
    name = "objectTransforms rewrite";
    description = "eval-time rewrite renames Secret -> SopsSecret and drops ConfigMap via rewrite -> null";
    assertions = [
      {
        description = "Secret was rewritten to SopsSecret";
        expression = objs;
        assertion = os: lib.any (o: o.kind == "SopsSecret") os;
      }
      {
        description = "ConfigMap was dropped (rewrite -> null)";
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
      {
        description = "tty was added to all containers in deployment";
        expression = objs;
        assertion =
          os:
          lib.all (c: c.tty)
            (lib.head (lib.filter (o: o.kind == "Deployment") os)).spec.template.spec.containers;
      }
      {
        description = "only one env was rewritten";
        expression = objs;
        assertion =
          os:
          let
            containers = (lib.head (lib.filter (o: o.kind == "Deployment") os)).spec.template.spec.containers;
            envs = lib.listToAttrs (lib.concatMap (c: c.env or [ ]) containers);
          in
          envs.a == "c" && envs.b == "b";
      }
      {
        description = "setting part to null removes the attribute";
        expression = objs;
        assertion =
          os:
          let
            labels = (lib.head (lib.filter (o: o.kind == "Deployment") os)).metadata.labels;
          in
          (builtins.hasAttr "bar" labels) && !(builtins.hasAttr "foo" labels);
      }
    ];
  };
}
