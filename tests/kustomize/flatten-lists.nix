{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  applications.test1.kustomize.applications.test1 = {
    kustomization = {
      src = ./manifests;
      path = "base";
    };
  };

  test = with lib; {
    name = "kustomize application with nested List object.";
    description = "Create an application with kustomize, splitting up List objects.";
    assertions = [
      {
        description = "ConfigMaps should be rendered correctly.";

        expression = filter (x: x.kind == "ConfigMap") apps.test1.objects;

        expected = [
          {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata.name = "cm-1";
            metadata.namespace = "test1";
            data.key = "value";
          }
          {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata.name = "cm-2";
            metadata.namespace = "test1";
            data.key = "value";
          }
          {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata.name = "cm-3";
            metadata.namespace = "test1";
            data.key = "value";
          }
        ];
      }
      {
        description = "ConfigMapLists should NOT be rendered.";

        expression = filter (x: x.kind == "ConfigMapList") apps.test1.objects;

        expected = [ ];
      }
      {
        description = "CustomList should be rendered intact.";

        expression = filter (x: x.kind == "CustomList") apps.test1.objects;

        expected = [
          {
            apiVersion = "custom/v1";
            kind = "CustomList";
            metadata.name = "custom-list";
            metadata.namespace = "test1";
            spec.items = [ 1 ];
          }
        ];
      }
    ];
  };
}
