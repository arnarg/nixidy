{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
  encryptedSecretFile = ./extra-raw-yamls/encrypted-secret.yaml;
in
{
  applications.demo = {
    namespace = "demo";
    resources.configMaps.demo-cm.data.hello = "world";
    extraRawYamls = [ encryptedSecretFile ];
  };

  test = with lib; {
    name = "extra raw yamls";
    description = ''
      Verify that `extraRawYamls` includes YAML files in the application output without
      parsing them into Nix, so manifests with schema-incompatible fields (e.g. SOPS
      metadata) survive intact.
    '';
    assertions = [
      {
        description = "Raw YAML path should be retrievable as-is via extraRawYamls.";
        expression = apps.demo.extraRawYamls;
        expected = [ encryptedSecretFile ];
      }
      {
        description = "Raw YAML should NOT appear in parsed `objects` (i.e. it isn't routed through kube.fromYAML).";
        expression = findFirst (
          x: x.kind or null == "Secret" && x.metadata.name or null == "encrypted-secret"
        ) null apps.demo.objects;
        expected = null;
      }
      {
        description = "Typed resources alongside extraRawYamls should still render normally.";
        expression = findFirst (
          x: x.kind == "ConfigMap" && x.metadata.name == "demo-cm"
        ) null apps.demo.objects;
        expected = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "demo-cm";
            namespace = "demo";
          };
          data.hello = "world";
        };
      }
      {
        description = "Built application output should contain the raw YAML file with unmodified contents.";
        expression = builtins.readFile (
          config.build.environmentPackage + "/${apps.demo.output.path}/encrypted-secret.yaml"
        );
        expected = builtins.readFile encryptedSecretFile;
      }
    ];
  };
}
