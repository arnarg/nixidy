# Object Transforms

Object transforms are a declarative rule engine for modifying rendered Kubernetes objects across your whole environment. A rule matches objects (or parts of them) and replaces or updates them. They are useful for cluster-wide policy (injecting labels or annotations, rewriting a kind, dropping resources). For runtime stages that post-process a rendered file, such as encrypting secrets on write, see [Post-processing](postprocessing.md).

Rules can be set environment-wide in `#!nix nixidy.objectTransforms`, or per application in `#!nix applications.<name>.objectTransforms`:

```nix
{
  nixidy.objectTransforms = {
    # applied to every application's objects
  };

  applications.my-app.objectTransforms = {
    # applied only to my-app's objects
  };
}
```

Where [Transformers](transformers.md) act on a single Helm release or Kustomize application, object transforms are matched against objects from _all_ applications, so they are a good fit for policy you want to apply consistently across an environment.

## A rule

Each rule selects objects with `match` and sets exactly one of `update`, `replace` or `transforms`:

```nix
{
  nixidy.objectTransforms.encrypt-secrets = {
    match.kind = "ExternalSecret";      # predicate or selector; omit to match every object

    # exactly one of the following:
    # 1. You can either update a part of the object
    update.spec.secretStoreRef = { kind = "ClusterSecretStore"; name = "foo"; };
    # 2. Or update it based on the old value
    update = old: { metadata.name = "secret-${old.metadata.name}"; };
    # 3. Or replace it entirely
    replace = { metadata = { … }; spec = { … }; };  # replace the whole object
    # 4. Or replace it based on the old value
    replace = old: old // { metadata = old.metadata // { name = "secret-${old.metadata.name}"; }; }
    # 5. Or run a nested transform.
    transforms = { … };
  }
}
```

## Accessing resource parts

Object transforms can act on whole resources, but you can also apply a transform to a part of a resource, such as:

```nix
{
    path = [ "spec" "template" "spec" "containers" "imagePullPolicy" ];
    replace = "Always";
}
```

Path segments iterate over lists and simply do not match if a field is missing, so the above rule will be executed for every container under `spec.template.spec.containers`, regardless of the resource's kind.

## Matching resources

`match` is either a predicate `#!nix resource -> bool` or a declarative selector that desugars to one:

```nix
{
  # selector form
  match = {
    kind = "Secret";
    metadata.namespace = [ "foo" "bar" ];
    metadata.labels."app.kubernetes.io/managed-by" = "nixidy";
  };

  # equivalent predicate form
  match =
    resource:
    resource.kind == "Secret"
    && ((resource.metadata.namespace or null) == "foo" || (resource.metadata.namespace or null) == "bar")
    && (resource.metadata.labels."app.kubernetes.io/managed-by" or null) == "nixidy";
}
```

Selector fields are ANDed together. If you provide a list as a value, at least one item of that list must match. Selectors behave in the same way as `path`s—they search in lists for a matching value, and only the specified part of an attrset must match (so in the above example, the `managed-by` label must match, but other labels may also be present).
The default matches _every_ object in scope, so omitting `match` applies the rule cluster-wide.

!!! note
    A rule's predicate runs against the object _as seen at that point in the pipeline_, i.e. after earlier transforms. A rule that renames a kind must be matched by its **new** kind in any later rule.

## Replacing and updating objects

`replace` is a function `resource -> resource`. Returning `#!nix null` drops the object entirely. Because it runs during evaluation, the result feeds every output consistently. Both `nixidy switch` and `nixidy apply` see the rewritten object.
If the provided value isn't a function, it's coerced to one, so `replace = { … };` is coerced to `replace = _: { … };` for your convenience.

```nix
{
  nixidy.objectTransforms = {
    # Add a managed-by label to every object in the environment.
    foo = {
      replace =
        resource:
        resource
        // {
          metadata = resource.metadata // {
            labels = (resource.metadata.labels or { }) // {
              "app.kubernetes.io/managed-by" = "nixidy";
            };
          };
        };
    };

    # Drop every HorizontalPodAutoscaler.
    bar = {
      match.kind = "HorizontalPodAutoscaler";
      replace = null;
    };
  };
}
``` 

`update = f` is applied as `replace = old: recursiveUpdate old (f old)`, so that you can easily do the above `foo` transform as:

```nix
{
  nixidy.objectTransforms = {
    foo = {
      update.metadata.labels."app.kubernetes.io/managed-by" = "nixidy";
    };
  };
}
```

Non-function value is coerced to a function in the same way as in `replace`, so it desugars to `replace = old: recursiveUpdate old ((_: { metadata.labels."app.kubernetes.io/managed-by" = "nixidy"; }) old)`.

## Nested transforms

Sometimes it's useful to find some resources, and then transform parts of them. For example:

```nix
{
  match = {
    metadata.labels."app.kubernetes.io/name" = "some-app";
  };
  transforms = {
    metadata = {
        path = [ "metadata" "labels" ];
        update."app.kubernetes.io/managed-by" = "nixidy";
    };
    template = {
        path = [ "spec" "template" "metadata" "labels" ];
        update."app.kubernetes.io/managed-by" = "nixidy";
    };
  };
}
```

The `transforms` attrset is exactly the same as `objectTransforms`, it just looks inside whatever the outer transform matches instead of the whole set of resources. You can nest such transforms multiple times.

## Ordering and scoping

Environment rules run first, then the matched application's rules, in the alphabetical order of their attribute names within each. Nested transforms likewise run in attribute-name order during evaluation of the outer transform.
