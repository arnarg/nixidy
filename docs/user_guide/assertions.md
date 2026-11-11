# Assertions & Warnings

Nixidy supports build-time assertions and warnings, similar to the NixOS module system. These allow you to define invariants that are checked during evaluation, catching misconfigurations early with clear error messages.

## Assertions

Assertions are conditions that **must** be true. If any assertion fails, the build will fail with a descriptive message.

### Per-application assertions

Each application can define its own assertions under `applications.<name>.assertions`:

```nix
{
  applications.my-app = {
    namespace = "my-app";
    resources = {
      deployments.my-app.spec = {
        # ...
      };
    };

    assertions = [
      {
        assertion = builtins.length (builtins.attrNames config.applications.my-app.resources.deployments) > 0;
        message = "my-app must have at least one deployment";
      }
    ];
  };
}
```

### Global assertions

Global assertions can be defined under `nixidy.assertions`. These are useful for checking invariants that span multiple applications:

```nix
{
  applications.app-a = { ... };
  applications.app-b = { ... };

  nixidy.assertions = [
    {
      assertion = config.applications ? app-a && config.applications ? app-b;
      message = "Both app-a and app-b must be defined";
    }
  ];
}
```

### Error output

When an assertion fails, the build will produce an error like:

```
error: failed assertions:
- assertion(my-app): my-app must have at least one deployment
```

The context (e.g. `my-app` or `global`) tells you where the assertion was defined.

## Warnings

Warnings are messages that are printed during evaluation but **do not** fail the build. They are useful for deprecation notices or highlighting potential issues.

### Per-application warnings

```nix
{
  applications.my-app = {
    namespace = "my-app";

    warnings = [
      {
        when = config.applications.my-app.createNamespace == false;
        message = "Not creating namespace for my-app, make sure it exists on the cluster";
      }
    ];
  };
}
```

### Shorthand for unconditional warnings

Warnings that should always be displayed can be written as plain strings:

```nix
{
  applications.my-app = {
    namespace = "my-app";
    warnings = [ "my-app is using a deprecated configuration, see the docs for migration steps" ];
  };
}
```

This is equivalent to `{ when = true; message = "..."; }`.

### Global warnings

```nix
{
  nixidy.warnings = [
    {
      when = config.nixidy.target.branch != "main";
      message = "Target branch is not 'main', make sure this is intentional";
    }
  ];
}
```

## When to use assertions vs. warnings

- Use **assertions** when the configuration is _invalid_ and should not be built. For example, missing required resources, conflicting settings, or values that would produce broken manifests.
- Use **warnings** when the configuration is technically valid but may indicate a mistake or something the user should be aware of. For example, deprecated options, unusual configurations, or migration reminders.

## Built-in reference validation

On top of your own assertions, nixidy can validate that every
ConfigMap or Secret **reference** made by a workload resolves to a
ConfigMap or Secret **defined** in the same environment. A typo in a
referenced name is caught at build time instead of failing when the
pod first schedules in the cluster:

```
error: failed assertions:
- assertion(global): application `my-app`: Deployment `my-app/web` references ConfigMap `foi` (spec.template.spec.volumes[0].configMap.name) which is not defined in any application
```

### Enabling and severity

The validation is opt-in:

```nix
{
  nixidy.validation.references.enable = true;
}
```

By default unresolved references *fail the build* (an assertion). Set
`nixidy.validation.references.severity = "warning";` to print them as
warnings instead and keep building.

### What is checked

Workload kinds checked (built-in):

- `Pod`
- `Deployment`
- `StatefulSet`
- `DaemonSet`
- `ReplicaSet`
- `Job`
- `CronJob`
  
The references checked are:

- volumes (`configMap.name`, `secret.secretName`,
  `persistentVolumeClaim.claimName`, projected volume sources)
- `envFrom` (`configMapRef`/`secretRef`),
- `env[].valueFrom` (`configMapKeyRef`/`secretKeyRef`),
- `serviceAccountName`
- `imagePullSecrets`
  
from `containers`, `initContainers` and `ephemeralContainers` alike.
References marked `optional: true` are skipped, as are references to
Kubernetes' auto-created resources (`kube-root-ca.crt` ConfigMap and
the `default` ServiceAccount).

Each failure reports the exact manifest field path of the broken
reference, so multiple references to the same missing resource
(e.g. several `env` vars pulling keys from one missing Secret) each
get their own line pointing at the offending field.

Definitions are indexed across the whole environment, so a workload in
one application may reference a resource defined in another
application as long as the namespaces match and the applications
target the *same cluster* (same `destination.name`, falling back to
`destination.server`). Objects rendered from Helm charts, Kustomize,
and `yamls` all count as definitions, as do a `StatefulSet`'s
`volumeClaimTemplates` (counted as `PersistentVolumeClaim` definitions
in the StatefulSet's namespace).

### Generated resources

Resources that are generated *in-cluster* by CRDs would otherwise be
flagged as missing. nixidy therefore ships with built-in rules mapping
well-known generator CRDs to the resources they create - a reference
to the generated resource resolves if the CRD object is defined
anywhere in the environment:

|CRD kind         |Generated kind|Name taken from                                          |
|-----------------|--------------|---------------------------------------------------------|
|`Certificate`    |`Secret`      |`spec.secretName`                                        |
|`ExternalSecret` |`Secret`      |`spec.target.name`, else the object's own name           |
|`SealedSecret`   |`Secret`      |`spec.template.metadata.name`, else the object's own name|
|`OnePasswordItem`|`Secret`      |the object's own name                                    |

Add rules for other operators:

```nix
{
  # Objects of kind "MyThing" generate a Secret named after spec.secret
  nixidy.validation.references.generators.Secret.MyThing.namePath = [
    "spec"
    "secret"
  ];
}
```

`generators` is an attribute set keyed by the generated kind and then
the generator CRD kind; user rules are merged with the built-ins, so
individual built-in rules can be overridden (e.g. adjust a built-in
`namePath`) without redefining the rest. `namePath` is optional; when
unset (or the path does not resolve to a string) the generated
resource is assumed to be named after the generator object itself.

### Custom workload kinds

The set of walked kinds is user-extensible, so CRDs containing pod
templates (e.g. Argo Rollouts, KEDA `ScaledJob`) can be checked too:

```nix
{
  nixidy.validation.references.workloads.Rollout.podSpecPath = [
    "spec"
    "template"
    "spec"
  ];
}
```

`workloads` is an attribute set keyed by resource kind. User entries
are *merged* with the built-in kinds. `podSpecPath` is the attribute
path to the pod spec within objects of that kind. Objects of kinds not
registered here are not checked.

### Limitations

- `extraRawYamls` are copied verbatim and never parsed, so references
  inside them are not checked, and resources defined only in them are
  not visible as definitions.
- `postProcessors` run after evaluation on the rendered files, so
  resources they add or modify are not visible to the validation.
- Clusters are keyed by `destination.name` when set, otherwise by
  `destination.server`. Applications that target the same cluster
  through different keys (e.g. one sets `destination.name =
  "in-cluster"` while another keeps the default `destination.server =
  "https://kubernetes.default.svc"`) cannot see each other's
  definitions, which can surface false positives. Keep the destination
  key consistent across applications sharing resources, or add
  `ignore` rules for the affected references.
- Only applications in `config.nixidy.publicApps` are considered —
  applications whose attribute name starts with `__` (like nixidy's
  internal `__bootstrap` app-of-apps application) are neither checked
  nor treated as sources of definitions.

### Ignoring references

```nix
{
  nixidy.validation.references.ignore = [
    # Matches any application
    { kind = "Secret"; name = "cluster-wide-pull-secret"; }

    # Scoped to one application, glob on the name
    { app = "my-app"; kind = "Secret"; name = "dyn-*"; }
  ];
}
```

Each ignore rule takes an optional `app` (application name or the
application's attribute key; `null` matches any), an optional `kind`
(`"ConfigMap"`, `"Secret"`, `"PersistentVolumeClaim"` or
`"ServiceAccount"`; `null` matches any), and a required `name` glob
pattern (`*` wildcards; everything else is matched literally).
