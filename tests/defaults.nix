{
  lib,
  config,
  ...
}: let
  defaultServer = "https://localhost:6443";
in {
  nixidy.defaults = {
    # Set the default destination server
    destination.server = defaultServer;

    # Turn on auto sync
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };
  };

  # Create an application that does not override
  # any defaults
  applications.test1.resources.namespaces.test1 = {};

  # Create an applicaton that does override defaults
  applications.test2 = {
    destination.server = "https://kubernetes.default.svc:6443";
    syncPolicy.autoSync.enable = false;
  };

  test = with lib; {
    name = "defaults";
    description = "Check that defaults get set on all generated applications.";
    assertions = [
      {
        description = "All applications should have defaults set unless overridden.";
        expression = config.applications.apps.resources.applications;
        assertion = expr: let
          # Get a list of all apps except "test2"
          # because that one has overridden the defaults
          apps =
            filter (app: app.name != "test2")
            (attrsToList expr);
        in
          all (
            app:
              app.value.spec.destination.server
              == defaultServer
              && app.value.spec.syncPolicy.automated != null
              && app.value.spec.syncPolicy.automated.prune
              && app.value.spec.syncPolicy.automated.selfHeal
          )
          apps;
      }
      {
        description = "Applications specific overrides should be applied instead of defaults.";
        expression = config.applications.apps.resources.applications.test2.spec;
        assertion = spec:
          spec.destination.server
          == "https://kubernetes.default.svc:6443"
          && spec.syncPolicy.automated == null;
      }
    ];
  };
}
