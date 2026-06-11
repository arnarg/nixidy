{ lib, config, ... }:
let
  layout = config.build.layout.myapp;
  byPath = p: lib.findFirst (s: s.path == p) null layout;

  cmSpec = byPath "myapp/ConfigMap-cm.yaml";
  nsSpec = byPath "myapp/Namespace-myapp.yaml";
  rawSpec = byPath "myapp/layout-extra.yaml";
  widgetSpec = byPath "myapp/Widget-shared.yaml";
in
{
  applications.myapp = {
    namespace = "myapp";
    createNamespace = true; # emits Namespace named "myapp"
    resources.configMaps.cm.data.FOO = "bar";
    extraRawYamls = [ ./fixtures/layout-extra.yaml ];
    yamls = [
      ''
        apiVersion: example.com/v1
        kind: Widget
        metadata:
          name: shared
          namespace: zeta
        ---
        apiVersion: example.com/v1
        kind: Widget
        metadata:
          name: shared
          namespace: alpha
      ''
    ];
  };

  test = {
    name = "layout FileSpec seam";
    description = "config.build.layout exposes per-app FileSpecs (path/source/class/rules)";
    assertions = [
      {
        description = "typed ConfigMap -> single-object rendered manifest FileSpec";
        expression = cmSpec;
        assertion =
          s:
          s != null
          && s.source ? rendered
          && lib.length s.source.rendered == 1
          && s.class == "manifests"
          && s.rules == [ ];
      }
      {
        description = "namespace resource classified as namespaces";
        expression = nsSpec;
        assertion = s: s != null && s.class == "namespaces";
      }
      {
        description = "extraRawYamls -> rawFile FileSpec, no rules, no resource";
        expression = rawSpec;
        assertion = s: s != null && s.source ? rawFile && s.rules == [ ] && s.resource == null;
      }
      {
        description = "multi-object group is namespace-sorted in source.rendered";
        expression = widgetSpec;
        assertion =
          s:
          s != null
          &&
            map (o: o.metadata.namespace) s.source.rendered == [
              "alpha"
              "zeta"
            ];
      }
    ];
  };
}
