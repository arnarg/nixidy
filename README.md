# nixidy

Kubernetes GitOps with nix and Argo CD.

> Kind of sounds like Nix CD.

Manage an entire Kubernetes cluster like it's NixOS, with the help of Argo CD.

## Why?

It's desirable to manage Kubernetes clusters in a declarative way using a git repository as a source of truth for manifests that should be deployed into the cluster. One popular solution that is often used to achieve this goal is [Argo CD](https://argo-cd.readthedocs.io/).

Argo CD has a concept of applications. Each application has an entrypoint somewhere in your git repository that is either a Helm chart, kustomize application, jsonnet files or just a directory of YAML files. All the resources that are output when templating the helm chart, kustomizing the kustomize application or are defined in the YAML files in the directory, make up the application and are (usually) deployed into a single namespace.

For those reasons these git repositories often need quite elaborate designs once many applications should be deployed, requiring use of application sets (generator for applications) or custom Helm charts just to render all the different applications of the repository.

On top of that it can be quite obscure _what exactly_ will be deployed by just looking at helm charts (along with all the values override, usually set for each environment) or the kustomize overlays (which often are many depending on number of environments/stages) without going in and just running `helm template` or `kubectl kustomize`.

Having dealt with these design decisions and pains that come with the different approaches I'm starting to use [The Rendered Manifests Pattern](https://akuity.io/blog/the-rendered-manifests-pattern/). While it's explained in way more detail in the linked blog post, basically it involves using your CI system to pre-render the helm charts or the kustomize overlays and commit all the rendered manifests to an environment branch (or go through a pull request review where you can review the _exact_ changes to your environment). That way you can just point Argo CD to your different directories full of rendered YAML manifests without having to do any helm templating or kustomize rendering.

### NixOS' Module System

I have been a user and a fan of NixOS for many years and how its module system works to recursively merge all configuration options that are set in many different modules.

I have _not_ been a fan of helm's string templating of a whitespace-sensitive configuration language or kustomize's repitition (defining a `kustomization.yaml` file for each layer statically listing files to include, some are json patches some are not...).

Therefore I made nixidy as an experiment to see if I can make something better (at least for myself). As all Argo CD applications are defined in a single configuration it can reference configuration options across applications and automatically generate an [App of Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern) bootstrapping all of them.

## Getting Started

Take a look at the [getting started guide](https://arnarg.github.io/nixidy/user_guide/getting_started/).

## Examples

- [nixidy-demo](https://github.com/arnarg/nixidy-demo)
- [arnarg's cluster config](https://github.com/arnarg/cluster)

## Special Thanks

[farcaller/nix-kube-generators](https://github.com/farcaller/nix-kube-generators) is used internally to pull and render Helm charts and some functions are re-exposed in the lib passed to modules in nixidy.

[hall/kubenix](https://github.com/hall/kubenix) project has code generation of nix module options for every standard kubernetes resource. Instead of doing this work in nixidy I simply import their generated resource options.
