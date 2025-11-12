{
  lib,
  config,
  ...
}:
{
  nixidy = {
    env = "prod";
    appendNameWithEnv = false;
  };

  # Create a a couple of applications
  applications = {
    test1 = { };
    test2 = { };
  };

  test = with lib; {
    name = "suffix-env-to-app-name";
    description = "Check that application name don't get the env as suffix.";
    assertions = [
      {
        description = "All applications should not have the -{env} suffix in their name";
        expression = config.applications.apps.resources.applications;
        assertion =
          expr:
          let
            apps = attrsToList expr;
          in
          all (app: app.value.metadata.name == app.name) apps;
      }
    ];
  };
}
