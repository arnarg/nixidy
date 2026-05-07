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
