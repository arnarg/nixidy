# A NixOS-style module that validates cross-resource references between
# applications. For example, a Deployment mounting a ConfigMap that is not
# defined anywhere in the environment will fail the build with an assertion.
{
  lib,
  config,
  ...
}:
let
  cfg = config.nixidy.validation.references;

  appsObjs = map (
    key:
    {
      name = config.applications.${key}.name;
      namespace = config.applications.${key}.namespace;
      cluster = lib.validation.clusterOf config.applications.${key};
      objects = (config.build._transformedObjects or { }).${key} or [ ];
    }
    // { inherit key; }
  ) config.nixidy.publicApps;

  unresolved = lib.validation.checkReferences {
    inherit appsObjs;
    ignore = cfg.ignore;
  };

  lines = map (
    m:
    "application `${m.app}`: ${m.workloadKind} `${m.ns}/${m.workloadName}` references ${m.kind} `${m.name}` (${m.path}) which is not defined in any application"
  ) unresolved;

  message = if unresolved == [ ] then null else lib.concatStringsSep "\n" lines;
in
{
  options.nixidy.validation.references = with lib; {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable build-time cross-resource reference validation.";
    };
    ignore = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            app = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Application name (or application attribute key) to scope the exclusion to (null matches any application).";
            };
            kind = mkOption {
              type = types.nullOr (
                types.enum [
                  "ConfigMap"
                  "Secret"
                ]
              );
              default = null;
              description = "Referenced resource kind to exclude (null matches any supported kind).";
            };
            name = mkOption {
              type = types.str;
              description = ''Glob pattern matching the referenced resource name (e.g. `"*"` or `"foo-*"`).'';
            };
          };
        }
      );
      default = [ ];
      description = "Rules ignoring specific unresolved resource references from failing validation.";
    };
  };

  config.nixidy.assertions = lib.mkIf cfg.enable (
    if unresolved == [ ] then
      [ ]
    else
      [
        {
          assertion = false;
          message = message;
        }
      ]
  );
}
