# Equivalence test for the native CRD module generator.
#
# `fromCRDModule` (native, returns a module value) must render byte-for-byte
# identically to `fromCRD` (builds a `.nix` file that gets imported) for the
# same CRD. We generate both from one small inline CRD, render a custom
# resource through each via `mkEnv`, and assert the rendered objects are equal.
#
# Returns a derivation that builds iff the two backends agree.
{
  pkgs,
  mkEnv,
  generators,
}:
let
  # A CRD shaped to exercise the type/coercion branches most at risk of
  # diverging between the two generator backends:
  #   - int-or-string                          (targetPort)
  #   - additionalProperties -> attrsOf         (labels)
  #   - array of submodules coerced by "name"   (ports)
  #   - array of submodules with patch-merge-key (env)
  #   - array left as a plain list via skipCoerceToList (volumes)
  #   - nested submodule                        (resources)
  #   - global ObjectMeta metadata ref          (every CRD)
  crdYaml = ''
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: foobars.stable.example.com
    spec:
      group: stable.example.com
      names:
        kind: FooBar
        plural: foobars
        singular: foobar
      scope: Namespaced
      versions:
        - name: v1
          served: true
          storage: true
          schema:
            openAPIV3Schema:
              type: object
              properties:
                spec:
                  type: object
                  properties:
                    image:
                      type: string
                    replicas:
                      type: integer
                    targetPort:
                      x-kubernetes-int-or-string: true
                    labels:
                      type: object
                      additionalProperties:
                        type: string
                    ports:
                      type: array
                      items:
                        type: object
                        properties:
                          name:
                            type: string
                          port:
                            type: integer
                    volumes:
                      type: array
                      items:
                        type: object
                        properties:
                          name:
                            type: string
                          path:
                            type: string
                    env:
                      type: array
                      x-kubernetes-patch-merge-key: key
                      items:
                        type: object
                        properties:
                          key:
                            type: string
                          value:
                            type: string
                    resources:
                      type: object
                      properties:
                        cpu:
                          type: string
                        memory:
                          type: string
                status:
                  type: object
                  properties:
                    availableReplicas:
                      type: integer
  '';

  src = pkgs.runCommand "foobar-crd-src" { } ''
    mkdir -p $out
    cp ${pkgs.writeText "foobar.yaml" crdYaml} $out/foobar.yaml
  '';

  args = {
    name = "foobar";
    inherit src;
    crds = [ "foobar.yaml" ];
    # Exercise the skip branch: `volumes` stays a plain list instead of being
    # coerced to an attrset-by-name.
    skipCoerceToList = {
      "stable.example.com.v1.FooBarSpec" = [ "volumes" ];
    };
  };

  # File backend: generate a .nix file, then import it back.
  fileMod = import (generators.fromCRD args);
  # Native backend: a module value, no file round-trip.
  nativeMod = generators.fromCRDModule args;

  render =
    crdMod:
    (mkEnv {
      inherit pkgs;
      modules = [
        {
          nixidy.target = {
            repository = "x";
            branch = "main";
          };
          # Base imports (k8s core + argocd) stay on; we only add the CRD
          # under test. The base modules don't define FooBar, so the
          # file-vs-native difference is isolated to this resource.
          nixidy.applicationImports = [ crdMod ];
          applications.test = {
            namespace = "default";
            resources."stable.example.com"."v1"."FooBar".myfoo.spec = {
              image = "nginx";
              replicas = 2;
              targetPort = 8080; # int-or-string
              labels.app = "demo"; # additionalProperties -> attrsOf str
              ports.http.port = 8080; # coerce-by-name -> attrset key becomes name
              env.FOO.value = "bar"; # coerce-by-key (patch-merge-key "key")
              volumes = [
                {
                  # skipped -> plain list
                  name = "data";
                  path = "/data";
                }
              ];
              resources = {
                cpu = "100m";
                memory = "128Mi";
              }; # nested submodule
            };
          };
        }
      ];
    }).config.applications.test.resources."stable.example.com"."v1"."FooBar".myfoo;

  equal = render fileMod == render nativeMod;
in
pkgs.runCommand "crd-module-equiv-test" { } (
  if equal then
    ''
      echo "PASS: fromCRDModule renders identically to fromCRD"
      touch $out
    ''
  else
    throw "fromCRDModule output differs from fromCRD output"
)
