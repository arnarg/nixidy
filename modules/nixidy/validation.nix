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
      objects = config.build._transformedObjects.${key} or [ ];
    }
    // {
      inherit key;
    }
  ) config.nixidy.publicApps;

  unresolved = lib.validation.checkReferences {
    inherit appsObjs;
    ignore = cfg.ignore;
    generators = cfg.generators;
    workloads = cfg.workloads;
  };

  # One line per unresolved reference
  line =
    m:
    "application `${m.app}`: ${m.workloadKind} `${m.ns}/${m.workloadName}` references ${m.kind} `${m.name}` (${m.path}) which is not defined in any application";
in
{
  options.nixidy.validation.references = with lib; {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable build-time cross-resource reference validation.";
    };
    severity = mkOption {
      type = types.enum [
        "error"
        "warning"
      ];
      default = "error";
      description = ''Whether unresolved references fail the build as an assertion (`"error"`) or print a build warning (`"warning"`).'';
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
              type = types.nullOr (types.enum lib.validation.definitionKinds);
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
      description = "Rules excluding specific unresolved resource references from failing validation.";
    };
    workloads = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.podSpecPath = mkOption {
            type = types.listOf types.str;
            description = "Attribute path to the pod spec within objects of this kind.";
          };
        }
      );
      default = { };
      description = ''
        Workload kinds (objects containing a pod spec) that are walked for
        resource references. Ships with the built-in pod-spec kinds (Pod,
        Deployment, StatefulSet, DaemonSet, ReplicaSet, Job, CronJob);
        extend it with your own CRDs, e.g.:

        `workloads.Rollout.podSpecPath = [ "spec" "template" "spec" ];`

        Objects of kinds not registered here are not checked.
      '';
    };
    generators = mkOption {
      type = types.submodule {
        options = genAttrs lib.validation.definitionKinds (
          kind:
          mkOption {
            type = types.attrsOf (
              types.submodule {
                options.namePath = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Attribute path to the generated resource's name (falls back to `metadata.name` when unset or empty).";
                };
              }
            );
            default = { };
            description = "CRD kinds that generate a `${kind}` in-cluster, keyed by generator kind.";
          }
        );
      };
      default = { };
      description = ''
        Rules describing CRDs that generate resources in-cluster (e.g. cert-manager
        `Certificate` generating a `Secret`), keyed by generated kind and then
        generator CRD kind. Only the supported reference kinds
        (${concatMapStringsSep ", " (k: "`${k}`") lib.validation.definitionKinds})
        are accepted as generated kinds. References to the generated resource resolve against
        these rules. nixidy ships with built-in rules for cert-manager
        `Certificate`, `ExternalSecret`, `SealedSecret` and `OnePasswordItem`
        generating `Secret`s; user rules are merged with the built-ins, e.g.:

        `generators.Secret.MyThing.namePath = [ "spec" "secret" ];`
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Seed the built-in workload kinds and generator rules regardless of
      # `enable`, so both tables are always fully populated and user
      # entries merge with the built-ins.
      nixidy.validation.references.workloads = lib.validation.defaultWorkloads;
      nixidy.validation.references.generators = lib.validation.defaultGenerators;
    }
    (lib.mkIf cfg.enable {

      nixidy = {
        assertions = lib.optionals (cfg.severity == "error") (
          map (m: {
            assertion = false;
            message = line m;
          }) unresolved
        );

        warnings = lib.optionals (cfg.severity == "warning") (
          map (m: {
            when = true;
            message = line m;
          }) unresolved
        );
      };
    })
  ];
}
