{
  lib,
  config,
  ...
}:
let
  ress = config.applications.test1.resources;
in
{
  applications = {
    test1.resources.pods.test.spec.containers.test = {
      image = "nginx";
      resources.limits = {
        cpu = 1.0;
        memory = "500Mi";
        "nvidia.com/gpu" = 1;
      };
    };
  };

  test = {
    name = "resources limits/requests types";
    description = "Check that resources requests and limits support extended types.";
    assertions = [
      {
        description = "Resource limits supports string, int and float.";
        expression = lib.head ress.pods.test.spec.containers;
        assertion =
          cnt:
          cnt.resources.limits.cpu == 1.0
          && cnt.resources.limits.memory == "500Mi"
          && cnt.resources.limits."nvidia.com/gpu" == 1;
      }
    ];
  };
}
