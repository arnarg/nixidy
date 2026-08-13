{
  pkgs,
  kubelib,
}:
let
  lib = import ./default.nix { inherit pkgs kubelib; };
in
{
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
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
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
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
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
      testNoLabels = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "argocd";
          };
        };
        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "argocd";
          };
        };
      };
      testSpecialTemplateLabels = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/name" = "chart";
            };
            template = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
                "helm.sh/chart" = "chart-0.1.0";
              };
              spec.containers = [
                {
                  name = "chart";
                  image = "nginx:latest";
                  ports = [
                    {
                      name = "http";
                      containerPort = 80;
                      protocol = "TCP";
                    }
                  ];
                }
              ];
            };
          };
        };
        expected = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            };
          };
          spec = {
            replicas = 1;
            selector.matchLabels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/name" = "chart";
            };
            template = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
              };
              spec.containers = [
                {
                  name = "chart";
                  image = "nginx:latest";
                  ports = [
                    {
                      name = "http";
                      containerPort = 80;
                      protocol = "TCP";
                    }
                  ];
                }
              ];
            };
          };
        };
      };
      testCronJobTemplateLabels = {
        expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
          apiVersion = "batch/v1";
          kind = "CronJob";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
              "helm.sh/chart" = "chart-0.1.0";
            };
          };
          spec = {
            schedule = "*/20 * * * *";
            jobTemplate = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
                "helm.sh/chart" = "chart-0.1.0";
              };
              spec.template = {
                metadata.labels = {
                  "app.kubernetes.io/instance" = "test1";
                  "app.kubernetes.io/managed-by" = "Helm";
                  "app.kubernetes.io/name" = "chart";
                  "helm.sh/chart" = "chart-0.1.0";
                };
                spec.containers = [
                  {
                    name = "chart";
                    image = "nginx:latest";
                    ports = [
                      {
                        name = "http";
                        containerPort = 80;
                        protocol = "TCP";
                      }
                    ];
                  }
                ];
              };
            };
          };
        };
        expected = {
          apiVersion = "batch/v1";
          kind = "CronJob";
          metadata = {
            name = "test1-chart";
            namespace = "test1";
            labels = {
              "app.kubernetes.io/instance" = "test1";
              "app.kubernetes.io/managed-by" = "Helm";
              "app.kubernetes.io/name" = "chart";
            };
          };
          spec = {
            schedule = "*/20 * * * *";
            jobTemplate = {
              metadata.labels = {
                "app.kubernetes.io/instance" = "test1";
                "app.kubernetes.io/managed-by" = "Helm";
                "app.kubernetes.io/name" = "chart";
              };
              spec.template = {
                metadata.labels = {
                  "app.kubernetes.io/instance" = "test1";
                  "app.kubernetes.io/managed-by" = "Helm";
                  "app.kubernetes.io/name" = "chart";
                };
                spec.containers = [
                  {
                    name = "chart";
                    image = "nginx:latest";
                    ports = [
                      {
                        name = "http";
                        containerPort = 80;
                        protocol = "TCP";
                      }
                    ];
                  }
                ];
              };
            };
          };
        };
      };
    }
    // (builtins.listToAttrs (
      map
        (kind: {
          name = "test${kind}MatchLabels";
          value = {
            expr = lib.kube.removeLabels [ "helm.sh/chart" ] {
              apiVersion = "apps/v1";
              inherit kind;
              metadata = {
                name = "test-${lib.toLower kind}";
                labels = {
                  "app.kubernetes.io/name" = "test";
                  "helm.sh/chart" = "test-chart";
                };
              };
              spec = {
                replicas = 1;
                selector.matchLabels = {
                  "app.kubernetes.io/name" = "test";
                  "helm.sh/chart" = "test-chart";
                };
              };
            };
            expected = {
              apiVersion = "apps/v1";
              inherit kind;
              metadata = {
                name = "test-${lib.toLower kind}";
                labels = {
                  "app.kubernetes.io/name" = "test";
                };
              };
              spec = {
                replicas = 1;
                selector.matchLabels = {
                  "app.kubernetes.io/name" = "test";
                };
              };
            };
          };
        })
        [
          "DaemonSet"
          "Deployment"
          "ReplicaSet"
          "StatefulSet"
        ]
    ));
  };

  # Regression tests for the ECMAScript-pattern guard in
  # pkgs/generators/compile/{runtime,generator}.nix. builtins.match compiles a
  # POSIX ERE and throws an uncatchable error on a pattern it cannot compile;
  # the guard translates the simple class escapes and otherwise skips, so a CRD
  # pattern can neither abort evaluation nor reject a value it should accept.
  withPattern =
    let
      rt = import ../pkgs/generators/compile/runtime.nix {
        lib = pkgs.lib;
        config = {
          defaults = [ ];
        };
        definitions = { };
      };
      # `(withPattern pattern str).check value`. Evaluating this forces
      # builtins.match for any pattern the guard deems compilable, so a pattern
      # that wrongly reached builtins.match with an uncompilable regex would
      # throw here and fail the test rather than pass silently.
      accepts = pattern: value: (rt.types.withPattern pattern rt.types.str).check value;
    in
    {
      # Class-free patterns are translated (\d \s \w and \/) and validated.
      testDigitsAccept = {
        expr = accepts "\\d+" "123";
        expected = true;
      };
      testDigitsReject = {
        expr = accepts "\\d+" "abc";
        expected = false;
      };
      testSlashTranslated = {
        expr = accepts "a\\/b" "a/b";
        expected = true;
      };
      testWordClassAccept = {
        expr = accepts "\\w+" "abc_1";
        expected = true;
      };
      testAnchoredLiteralAccept = {
        expr = accepts "^foo-bar$" "foo-bar";
        expected = true;
      };
      testAnchoredLiteralReject = {
        expr = accepts "^foo-bar$" "nope";
        expected = false;
      };

      # Patterns POSIX ERE cannot compile are skipped (the option keeps the base
      # `str` type): they must never abort evaluation and never reject a valid
      # value. Each previously either crashed eval or mis-validated.
      testCharacterClassSkipped = {
        # `[\w.-]+` was mis-translated to a class-in-class that rejected valid
        # values; skipping it means a valid value is accepted again.
        expr = accepts "[\\w.-]+" "my-app.v2";
        expected = true;
      };
      testBracketSubSyntaxSkipped = {
        # `[[:]` opens a POSIX bracket sub-expression and threw at compile time.
        expr = accepts "[[:]" "anything";
        expected = true;
      };
      testIntervalSkipped = {
        expr = accepts "a{2,3}" "anything";
        expected = true;
      };
      testUnsupportedEscapeSkipped = {
        expr = accepts "\\bword\\b" "anything";
        expected = true;
      };
      testLookaroundSkipped = {
        expr = accepts "(?=x)" "anything";
        expected = true;
      };
      testCidrLikePatternSkipped = {
        # Cilium-style IP pattern (classes + intervals): skipped, not crashed —
        # the regression that motivated the fix. A non-matching value is accepted
        # because the check is skipped, confirming it is not (mis-)validated.
        expr = accepts "([0-9]{1,3}\\.){3}[0-9]{1,3}" "not-an-ip";
        expected = true;
      };
    };
}
