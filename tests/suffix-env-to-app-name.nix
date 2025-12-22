{
  lib,
  config,
  ...
}:
{
  nixidy = {
    env = "prod";
    appendNameWithEnv = true;
  };

  # Create a a couple of applications
  applications = {
    test1 = { };
    test2 = { };
  };

  test = with lib; {
    name = "suffix-env-to-app-name";
    description = "Check that application name get the env as suffix.";
    assertions = [
      {
        description = "All applications should have the -{env} suffix in their name";
        expression = config.applications.apps.resources.applications;
        assertion =
          expr:
          let
            apps = attrsToList expr;
          in
          all (app: app.value.metadata.name == "${app.name}-${config.nixidy.env}") apps;
      }

      {
        description = "The app of apps should not get the suffix.";
        expression = config.applications.__bootstrap.resources.applications.${config.nixidy.appOfApps.name};
        assertion = app: app.metadata.name == config.nixidy.appOfApps.name;
      }
    ];
  };
}
