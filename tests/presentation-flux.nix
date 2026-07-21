# Flux backend proof: with `backend = "flux"`, the `__flux-system` synthetic app
# carries raw GitRepository + per-app Kustomization objects derived from
# `nixidy.target` + each app's output path.
{ lib, config, ... }:
let
  objects = config.applications.__flux-system.objects;
  gitRepos = lib.filter (o: o.kind or null == "GitRepository") objects;
  kustomizations = lib.filter (o: o.kind or null == "Kustomization") objects;
  myappKust = lib.filter (o: (o.metadata.name or null) == "myapp") kustomizations;
in
{
  nixidy.presentation.backend = "flux";
  # The test harness (modules/testing/eval.nix) already sets repository/branch;
  # override repository with mkForce so the GitRepository URL assertion is exact.
  nixidy.target = {
    repository = lib.mkForce "https://example.com/repo.git";
    branch = lib.mkForce "main";
    rootPath = "./manifests";
  };

  applications.myapp = {
    namespace = "myapp";
    resources.configMaps.cm.data.x = "y";
  };

  test = {
    name = "flux backend synthesis";
    description = "backend=flux synthesizes raw GitRepository + per-app Kustomization objects in __flux-system";
    assertions = [
      {
        description = "__flux-system carries a GitRepository with the target repository URL";
        expression = gitRepos;
        assertion =
          gr:
          lib.length gr == 1
          && (lib.head gr).spec.url == "https://example.com/repo.git"
          && (lib.head gr).spec.ref.branch == "main";
      }
      {
        description = "a Kustomization for myapp exists with the right sourceRef and path";
        expression = myappKust;
        assertion =
          ks:
          let
            k = lib.head ks;
          in
          lib.length ks == 1
          && k.spec.sourceRef.name == "flux-system"
          && k.spec.sourceRef.kind == "GitRepository"
          # Exact path (rootPath "./manifests" + output.path "myapp") — locks the
          # format so a double-`./`-prefix regression can't slip through.
          && k.spec.path == "./manifests/myapp";
      }
    ];
  };
}
