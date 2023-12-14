{
  lib,
  klib,
  pkgs,
}: rec {
  /*
  Convert a list of kubernetes manifests (already parsed from YAML/JSON)
  to the resources format used in nixidy.

  Type:
    fromManifests :: [AttrSet] -> AttrSet

  Example:
    fromManifests [
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = "default";
      }
      {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "config";
          namespace = "default";
        };
        data = {
          key1 = "val1";
          key2 = "val2";
        };
      }
    ]
    => {
      v1 = {
        Namespace.default = {};
        ConfigMap.config = {
          metadata.namespace = "default";
          data = {
            key1 = "val1";
            key2 = "val2";
          };
        };
      };
    }
  */
  fromManifests =
    # List of kubernetes manifests in nix AttrSet.
    manifests:
      lib.updateManyAttrsByPath (map (res: {
          path = [res.apiVersion res.kind res.metadata.name];
          update = _: removeAttrs res ["apiVersion" "kind"];
        })
        manifests) {};

  /*
  Convert a list of kubernetes manifests in YAML to the resources format
  used in nixidy.

  Type:
    fromManifestYAMLs :: [String] -> AttrSet

  Example:
    fromManifestYAMLs [
      ''
        apiVersion: v1
        kind: Namespace
        metadata:
          name: default
      ''
      ''
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: config
          namespace: default
        data:
          key1: val1
          key2: val2
      ''
    ]
    => {
      v1 = {
        Namespace.default = {};
        ConfigMap.config = {
          metadata.namespace = "default";
          data = {
            key1 = "val1";
            key2 = "val2";
          };
        };
      };
    }
  */
  fromManifestYAMLs =
    # List of kubernetes manifests in YAML.
    yamls: let
      parsed = lib.flatten (map lib.kube.fromYAML yamls);
    in
      fromManifests parsed;

  /*
  Read and convert a list of kubernetes manifests in files to the resources
  format used in nixidy.

  Type:
    fromManifestFiles :: [Derivation] -> AttrSet

  Example:
    fromManifestFiles [
      ./namespace.yaml
      ./configmap.yaml
    ]
    => {
      v1 = {
        Namespace.default = {};
        ConfigMap.config = {
          metadata.namespace = "default";
          data = {
            key1 = "val1";
            key2 = "val2";
          };
        };
      };
    }
  */
  fromManifestFiles =
    # List of derivations where the output is a single file containing
    # kubernetes manifests in YAML.
    files: let
      readFiles = map builtins.readFile files;
    in
      fromManifestYAMLs readFiles;

  /*
  Render a kustomization and convert the resources to the resources format
  used in nixidy.

  Type:
    fromKustomization :: AttrSet -> AttrSet

  Example:
    fromKustomization {
      name = "argocd";
      src = pkgs.fetchFromGitHub {
        owner = "argoproj";
        repo = "argo-cd";
        rev = "v2.9.3";
        hash = "sha256-GaY4Cw/LlSwy35umbB4epXt6ev8ya19UjHRwhDwilqU=";
      };
      path = "manifests/cluster-install";
      namespace = "argocd";
    }
    => {
      v1 = {
        Namespace.argocd = {};
      };
      # ...
    }
  */
  fromKustomization = args @ {
    # Name is only used for derivation name.
    name,
    # Derivation containing the kustomization entrypoint and
    # all relative bases that it might reference.
    src,
    # Relative path from the base of `src` to the kustomization
    # folder to render.
    path,
    # Override namespace in kustomization.yaml.
    namespace ? null,
  }:
    pkgs.lib.pipe
    args [
      lib.kustomize.buildKustomization
      lib.singleton
      fromManifestFiles
    ];

  /*
  Render a helm chart and convert the resources to the resources format
  used in nixidy.
  This function uses nix-kube-generators' `buildHelmChart` to do the
  helm templating.

  Type:
    fromHelmChart :: AttrSet -> AttrSet

  Example:
    fromHelmChart {
      name = "argocd";
      chart = lib.helm.downloadHelmChart {
        repo = "https://argoproj.github.io/argo-helm/";
        chart = "argo-cd";
        version = "5.51.4";
        chartHash = "sha256-LOEJ5mYaHEA0RztDkgM9DGTA0P5eNd0SzSlwJIgpbWY=";
      };
      namespace = "argocd";
      values = {
        server.replicas = 2;
      };
    }
    => {
      v1 = {
        Namespace.argocd = {};
      };
      # ...
    }
  */
  fromHelmChart = args:
    pkgs.lib.pipe
    args [
      klib.fromHelm
      fromManifests
    ];
}
