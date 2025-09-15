{
  pkgs,
  lib ? pkgs.lib,
  kubelib,
}:
let
  klib = kubelib.lib { inherit pkgs; };
in
lib.extend (
  self: old:
  let
    params = {
      inherit pkgs klib;
      lib = self;
    };
  in
  {
    kustomize = import ./kustomize.nix params;
    helm = import ./helm.nix params;
    kube = import ./kube.nix params;
  }
)
