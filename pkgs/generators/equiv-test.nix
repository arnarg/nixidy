# Tests for the CRD value accessors. Every accessor that returns Nix values
# must agree with the file generator and with its src/chart counterpart:
#
#   - fromCRDModule       renders identically to fromCRD (file)
#   - fromChartCRDModule  renders identically to fromCRDModule for the same CRD
#   - crdObjects          returns the raw CRD manifests (+ kindFilter narrows)
#   - crdObjectsFromChart returns the same objects as crdObjects for the same CRD
#   - the chart accessors honor `kubeVersion`
#
# Returns a derivation that builds iff every check passes.
{
  pkgs,
  mkEnv,
  generators,
}:
let
  lib = pkgs.lib;

  # ── A FooBar CRD, as both a `src` tree and a local helm chart ──────────────
  # Shaped to exercise the at-risk type/coercion branches: int-or-string
  # (targetPort), additionalProperties→attrsOf (labels), coerce-by-name (ports),
  # patch-merge-key (env), skipCoerceToList (volumes), nested submodule
  # (resources), and the global ObjectMeta metadata ref.
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
                      minimum: 1
                      maximum: 10
                    cpuShares:
                      type: integer
                      multipleOf: 2
                    mode:
                      type: string
                      enum:
                        - fast
                        - slow
                    hostname:
                      type: string
                      minLength: 1
                      maxLength: 63
                      pattern: ^[a-z0-9-]+$
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

  # Local helm chart shipping the same CRD in crds/ (helm --include-crds copies
  # crds/ verbatim, so the chart path must match the src path exactly).
  chart = pkgs.runCommand "foobar-chart" { } ''
    mkdir -p $out/crds
    cp ${pkgs.writeText "Chart.yaml" ''
      apiVersion: v2
      name: foobar
      version: 0.0.0
    ''} $out/Chart.yaml
    cp ${pkgs.writeText "foobar.yaml" crdYaml} $out/crds/foobar.yaml
  '';

  # A chart whose CRD is *templated* (in templates/, not crds/) and embeds the
  # helm `.Capabilities.KubeVersion` — so a passed kubeVersion is observable.
  verChart = pkgs.runCommand "ver-chart" { } ''
    mkdir -p $out/templates
    cp ${pkgs.writeText "Chart.yaml" ''
      apiVersion: v2
      name: ver
      version: 0.0.0
    ''} $out/Chart.yaml
    cp ${pkgs.writeText "crd.yaml" ''
      apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      metadata:
        name: vers.test.example.com
        annotations:
          test/kube-version: "{{ .Capabilities.KubeVersion.Version }}"
      spec:
        group: test.example.com
        names:
          kind: Ver
          plural: vers
          singular: ver
        scope: Namespaced
        versions:
          - name: v1
            served: true
            storage: true
            schema:
              openAPIV3Schema:
                type: object
    ''} $out/templates/crd.yaml
  '';

  skipCoerceToList = {
    "stable.example.com.v1.FooBarSpec" = [ "volumes" ];
  };

  # ── The accessors under test ───────────────────────────────────────────────
  fileMod = import (
    generators.fromCRD {
      name = "foobar";
      inherit src skipCoerceToList;
      crdFiles = [ "foobar.yaml" ];
    }
  );
  nativeMod = generators.fromCRDModule {
    name = "foobar";
    inherit src skipCoerceToList;
    crdFiles = [ "foobar.yaml" ];
  };
  chartMod = generators.fromChartCRDModule {
    name = "foobar";
    inherit chart skipCoerceToList;
    kindFilter = [ "FooBar" ];
  };

  srcObjs = generators.crdObjects {
    inherit src;
    crdFiles = [ "foobar.yaml" ];
  };
  chartObjs = generators.crdObjectsFromChart {
    name = "foobar";
    inherit chart;
  };
  verObjs =
    kubeVersion:
    generators.crdObjectsFromChart {
      name = "ver";
      chart = verChart;
      inherit kubeVersion;
    };

  # Render a FooBar resource through a CRD type module (via mkEnv). Base imports
  # (k8s core + argocd) provide ObjectMeta; the base doesn't define FooBar, so
  # any difference is isolated to this resource.
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
          nixidy.applicationImports = [ crdMod ];
          applications.test = {
            namespace = "default";
            resources."stable.example.com"."v1"."FooBar".myfoo.spec = {
              image = "nginx";
              replicas = 2;
              cpuShares = 4;
              mode = "fast";
              hostname = "my-host";
              targetPort = 8080;
              labels.app = "demo";
              ports.http.port = 8080;
              env.FOO.value = "bar";
              volumes = [
                {
                  name = "data";
                  path = "/data";
                }
              ];
              resources = {
                cpu = "100m";
                memory = "128Mi";
              };
            };
          };
        }
      ];
    }).config.applications.test.resources."stable.example.com"."v1"."FooBar".myfoo;

  # `specialMapKeys` is exposed only on the *module* accessors — `fromCRD` does
  # not take it — so it can't be diffed against the file backend. Exercise the
  # value backend's branch directly by rendering `spec.ports` as a *list* of
  # name-less entries: coerceAttrsOfSubmodulesToListByKey synthesizes the merge
  # key from `specialMapKeys` for entries lacking `name`, so distinct key values
  # keep entries separate while the empty default collapses them.
  renderPorts =
    specialMapKeys: portsList:
    (mkEnv {
      inherit pkgs;
      modules = [
        {
          nixidy.target = {
            repository = "x";
            branch = "main";
          };
          nixidy.applicationImports = [
            (generators.fromCRDModule {
              name = "foobar";
              inherit src skipCoerceToList specialMapKeys;
              crdFiles = [ "foobar.yaml" ];
            })
          ];
          applications.test = {
            namespace = "default";
            resources."stable.example.com"."v1"."FooBar".myfoo.spec.ports = portsList;
          };
        }
      ];
    }).config.applications.test.resources."stable.example.com"."v1"."FooBar".myfoo.spec.ports;

  # Render a FooBar with one spec field set to an out-of-bounds value, then
  # deep-force it. The override is part of the module *config*, so a working
  # validator turns the render into a type error, which `tryEval` reports as
  # `success == false` → we return `true` (rejected).
  rejects =
    override:
    let
      rendered =
        (mkEnv {
          inherit pkgs;
          modules = [
            {
              nixidy.target = {
                repository = "x";
                branch = "main";
              };
              nixidy.applicationImports = [ nativeMod ];
              applications.test = {
                namespace = "default";
                resources."stable.example.com"."v1"."FooBar".myfoo.spec = override;
              };
            }
          ];
        }).config.applications.test.resources."stable.example.com"."v1"."FooBar".myfoo;

      result = builtins.tryEval (lib.deepSeq rendered.spec rendered.spec);
    in
    !result.success;

  checks = {
    "fromCRDModule == fromCRD (file)" = render nativeMod == render fileMod;
    "fromChartCRDModule == fromCRDModule" = render chartMod == render nativeMod;

    "crdObjects returns the CRD" =
      lib.length srcObjs == 1 && (lib.head srcObjs).spec.names.kind == "FooBar";

    "crdObjects kindFilter hit" =
      lib.length (
        generators.crdObjects {
          inherit src;
          crdFiles = [ "foobar.yaml" ];
          kindFilter = [ "FooBar" ];
        }
      ) == 1;

    "crdObjects kindFilter miss" =
      generators.crdObjects {
        inherit src;
        crdFiles = [ "foobar.yaml" ];
        kindFilter = [ "Nope" ];
      } == [ ];

    # Deprecated `crds` alias still resolves (src-based → crdFiles).
    "crdObjects deprecated `crds` alias == `crdFiles`" =
      generators.crdObjects {
        inherit src;
        crds = [ "foobar.yaml" ];
      } == srcObjs;

    # Deprecated `crds` alias still resolves (chart-based → kindFilter).
    "crdObjectsFromChart deprecated `crds` alias == `kindFilter`" =
      generators.crdObjectsFromChart {
        name = "foobar";
        inherit chart;
        crds = [ "FooBar" ];
      } == generators.crdObjectsFromChart {
        name = "foobar";
        inherit chart;
        kindFilter = [ "FooBar" ];
      };

    # Value backend honors specialMapKeys (module-only arg). Two name-less ports
    # with distinct `port` values: a `port` merge key keeps them separate (2);
    # the empty default collapses them to one (1).
    "fromCRDModule honors specialMapKeys (value backend)" =
      let
        portsList = [
          { port = 1; }
          { port = 2; }
        ];
        withKey = renderPorts { "stable.example.com.v1.FooBarSpec".ports = [ "port" ]; } portsList;
        without = renderPorts { } portsList;
      in
      lib.length withKey == 2 && lib.length without == 1;

    "crdObjectsFromChart == crdObjects" = chartObjs == srcObjs;

    "crdObjectsFromChart honors kubeVersion" =
      let
        ann = kv: (lib.head (verObjs kv)).metadata.annotations."test/kube-version";
      in
      lib.hasInfix "1.31" (ann "v1.31.0")
      && lib.hasInfix "1.40" (ann "v1.40.0")
      && ann "v1.31.0" != ann "v1.40.0";

    # Validators reject out-of-bounds values. `tryEval` catches the type error
    # thrown by the failing `addCheck`; a rejected value yields success=false.
    # Rendering goes through the value backend (fromCRDModule), so these checks
    # pin the *runtime* rejection while the parity check above pins the types.
    "validator rejects integer below minimum" = rejects { replicas = 0; };
    "validator rejects integer above maximum" = rejects { replicas = 11; };
    "validator rejects non-multipleOf integer" = rejects { cpuShares = 3; };
    "validator rejects value outside enum" = rejects { mode = "medium"; };
    "validator rejects string violating pattern" = rejects { hostname = "Bad_Host"; };
  };

  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
pkgs.runCommand "crd-accessor-test" { } (
  if failed == [ ] then
    ''
      echo "PASS: ${toString (lib.length (lib.attrNames checks))} CRD accessor checks"
      touch $out
    ''
  else
    throw "CRD accessor checks failed: ${lib.concatStringsSep "; " failed}"
)
