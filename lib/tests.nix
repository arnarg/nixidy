{
  pkgs,
  kubelib,
}: let
  lib = import ./default.nix {inherit pkgs kubelib;};
in {
  kube = {
    fromYAML = {
      testSingleObject = {
        expr = lib.kube.fromYAML ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: default
        '';
        expected = [
          {
            apiVersion = "v1";
            kind = "Namespace";
            metadata.name = "default";
          }
        ];
      };
      testMultipleObjects = {
        expr = lib.kube.fromYAML ''
          apiVersion: v1
          kind: Namespace
          metadata:
            name: default
          ---
          apiVersion: v1
          kind: Namespace
          metadata:
            name: kube-system
        '';
        expected = [
          {
            apiVersion = "v1";
            kind = "Namespace";
            metadata.name = "default";
          }
          {
            apiVersion = "v1";
            kind = "Namespace";
            metadata.name = "kube-system";
          }
        ];
      };
    };

    fromOctal = {
      testConvertToCorrectInteger = {
        expr = lib.kube.fromOctal "0555";
        expected = 365;
      };
      testWithOctalPrefix = {
        expr = lib.kube.fromOctal "0o555";
        expected = 365;
      };
    };

    removeLabels = {
      testLabelPresent = {
        expr = lib.kube.removeLabels ["helm.sh/chart"] {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
              "helm.sh/chart" = "argo-cd-5.51.6";
            };
          };
        };
        expected = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
            };
          };
        };
      };
      testLabelAbsent = {
        expr = lib.kube.removeLabels ["helm.sh/chart"] {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
              "app" = "argocd";
            };
          };
        };
        expected = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "argocd-cm";
            labels = {
              "app.kubernetes.io/name" = "argocd-cm";
              "app" = "argocd";
            };
          };
        };
      };
    };
  };
}
