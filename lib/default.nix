{
  pkgs,
  lib ? pkgs.lib,
  kubelib,
}: let
  klib = kubelib.lib {inherit pkgs;};
in
  lib.extend (self: old: let
    params = {
      inherit pkgs klib;
      lib = self;
    };
  in {
    kustomize = import ./kustomize.nix params;
    helm = import ./helm.nix params;
    kube = import ./kube.nix params;

    mkApplication = {
      name,
      namespace,
      resources ? {},
      YAMLs ? [],
    }: {
      inherit name namespace;
      resources = lib.mkMerge [resources (self.resources.fromManifestYAMLs YAMLs)];
    };
  })
