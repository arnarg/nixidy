# Transformers

Nixidy supports adding a transformers to Helm releases and Kustomize applications. A transformer is only a function that takes in a list of Kubernetes manifests in attribute sets and returns the same (`[AttrSet] -> [AttrSet]`). It is called _after_ the manifests have been rendered and parsed into nix but _before_ they're transformed into the nixidy form (`<group>.<version>.<kind>.<name>`) and can be used to modify the resources.

Transformers can be set globally in `#!nix nixidy.defaults.helm.transformer` for Helm releases and `#!nix nixidy.defaults.kustomize.transformer` for kustomize applications.

## Remove Version Specific Labels

It's very common that helm charts will add the labels `helm.sh/chart` and `app.kubernetes.io/version` to _all_ resources it renders. This can produce _very_ big diffs when they're updated and nixidy renders them and commits the manifests to a git branch. The changes in these labels are not very relevant and will mostly just be noise to distract from the actual relevant changes of the rendered output.

A transformer can be used to filter out these labels.

```nix
{
  applications.argocd.helm.releases.argocd = {
    # ...

    # Remove the following labels from all manifests
    transformer = map (lib.kube.removeLabels [
      "app.kubernetes.io/version"
      "helm.sh/chart"
    ]);
  }
}
```

Here we use map to call `#!nix lib.kube.removeLabels` on each manifest in the list to remove the specified labels.
The example uses function currying, this is equivalent to `#!nix manifests: map (m: lib.kube.removeLabels ["..."] m) manifests`.
