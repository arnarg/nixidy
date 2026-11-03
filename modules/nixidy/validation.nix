{
  lib,
  config,
  ...
}:
let
  cfg = config.nixidy.validation;

  # Workload kinds whose pod-specs we walk for ConfigMap/Secret references.
  workloadKinds = [
    "Pod"
    "Deployment"
    "StatefulSet"
    "DaemonSet"
    "ReplicaSet"
    "Job"
    "CronJob"
  ];

  orList = v: if builtins.isList v then v else [ ];

  # Walk a nested attribute path safely; null on any missing/non-attrs hop.
  pick =
    obj: path:
    builtins.foldl' (
      a: p: if a != null && builtins.isAttrs a && a ? ${p} then a.${p} else null
    ) obj path;

  namedRef =
    kind: name: optional:
    if name == null || name == "" || !builtins.isString name then
      null
    else
      {
        kind = kind;
        name = name;
        optional = optional == true;
      };

  selRef =
    kind: sel:
    if sel == null || !builtins.isAttrs sel then
      null
    else
      namedRef kind (sel.name or null) (sel.optional or false);

  globToRegex = pat: lib.concatMapStringsSep ".*" lib.escapeRegex (lib.splitString "*" pat);
  globMatches = pat: value: (builtins.match (globToRegex pat) value) != null;

  effectiveNamespace =
    app: obj:
    let
      ns = obj.metadata.namespace or null;
    in
    if ns == null || ns == "" then app.namespace else ns;

  podSpecOf =
    kind: obj:
    let
      walk =
        obj: path:
        builtins.foldl' (
          a: p: if a != null && builtins.isAttrs a && a ? ${p} then a.${p} else { }
        ) obj path;
    in
    if kind == "Pod" then
      obj.spec or { }
    else if kind == "CronJob" then
      walk obj [
        "spec"
        "jobTemplate"
        "spec"
        "template"
        "spec"
      ]
    else
      walk obj [
        "spec"
        "template"
        "spec"
      ];

  # Kubernetes auto-creates this ConfigMap in every namespace.
  systemNames = [ "kube-root-ca.crt" ];

  # Cluster identifier an app targets: `destination.name` (a registered
  # ArgoCD cluster name) when set, else `destination.server`. Apps using
  # the default destination get their server, ensuring definitions and
  # references resolve only within the same destination cluster.
  clusterOf =
    app:
    if app.destination.name != null then
      app.destination.name
    else if app.destination.server != null then
      app.destination.server
    else
      "";

  refsFromPodSpec =
    ps:
    let
      volumeRefs = lib.concatMap (
        v:
        let
          proj = orList (
            pick v [
              "projected"
              "sources"
            ]
          );
        in
        lib.filter (r: r != null) (
          [
            (namedRef "ConfigMap"
              (pick v [
                "configMap"
                "name"
              ])
              (
                pick v [
                  "configMap"
                  "optional"
                ]
              )
            )
            (namedRef "Secret"
              (pick v [
                "secret"
                "secretName"
              ])
              (
                pick v [
                  "secret"
                  "optional"
                ]
              )
            )
          ]
          ++ map (s: selRef "ConfigMap" (pick s [ "configMap" ])) proj
          ++ map (s: selRef "Secret" (pick s [ "secret" ])) proj
        )
      ) (orList (pick ps [ "volumes" ]));

      containerRefs =
        containers:
        lib.concatMap (
          c:
          let
            envFrom = orList (pick c [ "envFrom" ]);
            env = orList (pick c [ "env" ]);
          in
          lib.filter (r: r != null) (
            map (e: selRef "ConfigMap" (pick e [ "configMapRef" ])) envFrom
            ++ map (e: selRef "Secret" (pick e [ "secretRef" ])) envFrom
            ++ map (
              e:
              selRef "ConfigMap" (
                pick e [
                  "valueFrom"
                  "configMapKeyRef"
                ]
              )
            ) env
            ++ map (
              e:
              selRef "Secret" (
                pick e [
                  "valueFrom"
                  "secretKeyRef"
                ]
              )
            ) env
          )
        ) containers;

      pullRefs = map (s: selRef "Secret" s) (orList (pick ps [ "imagePullSecrets" ]));
    in
    lib.filter (r: !(lib.elem r.name systemNames)) (
      volumeRefs
      ++ containerRefs (orList (pick ps [ "containers" ]))
      ++ containerRefs (orList (pick ps [ "initContainers" ]))
      ++ pullRefs
      ++ containerRefs (orList (pick ps [ "ephemeralContainers" ]))
    );

  objectRefs =
    app: obj:
    let
      kind = obj.kind or "";
    in
    if !lib.elem kind workloadKinds then
      [ ]
    else
      let
        ps = podSpecOf kind obj;
        ns = effectiveNamespace app obj;
        cluster = app.cluster;
        workload = "${kind}/${obj.metadata.name or obj.metadata.generateName or "<unnamed>"}";
        refs = lib.unique (
          lib.filter (r: r != null && r.optional != true && r.name != "") (refsFromPodSpec ps)
        );
      in
      map (r: {
        app = app.name;
        appKey = app.key;
        workload = workload;
        kind = r.kind;
        name = r.name;
        ns = ns;
        cluster = cluster;
      }) refs;

  check =
    appsObjs:
    let
      defs = builtins.listToAttrs (
        map (d: lib.nameValuePair "${d.cluster}|${d.kind}|${d.name}|${d.ns}" true) (
          lib.concatMap (
            app:
            lib.concatMap (
              obj:
              let
                kind = obj.kind or "";
              in
              if kind != "ConfigMap" && kind != "Secret" then
                [ ]
              else
                [
                  {
                    cluster = app.cluster;
                    kind = kind;
                    name = obj.metadata.name or "";
                    ns = effectiveNamespace app obj;
                  }
                ]
            ) app.objects
          ) appsObjs
        )
      );

      allRefs = lib.concatMap (app: lib.concatMap (objectRefs app) app.objects) appsObjs;

      missing = lib.filter (r: !(defs ? "${r.cluster}|${r.kind}|${r.name}|${r.ns}")) allRefs;

      isExcluded =
        r:
        lib.any (
          e:
          (e.app == null || e.app == r.app || e.app == r.appKey)
          && (e.kind == null || e.kind == r.kind)
          && globMatches e.name r.name
        ) cfg.exclusions;
    in
    lib.filter (r: !(isExcluded r)) missing;
in
{
  options.nixidy.validation = with lib; {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable build-time cross-resource reference validation.";
    };
    exclusions = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            app = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Application name (or application attribute key) to scope the exclusion to (null matches any application).";
            };
            kind = mkOption {
              type = types.nullOr (
                types.enum [
                  "ConfigMap"
                  "Secret"
                ]
              );
              default = null;
              description = "Referenced resource kind to exclude (null matches any supported kind).";
            };
            name = mkOption {
              type = types.str;
              description = ''Glob pattern matching the referenced resource name (e.g. `"*"` or `"foo-*"`).'';
            };
          };
        }
      );
      default = [ ];
      description = "Rules excluding specific unresolved resource references from failing validation.";
    };
  };

  config.nixidy.assertions = lib.mkIf cfg.enable (
    let
      appsObjs = map (key: {
        name = config.applications.${key}.name;
        namespace = config.applications.${key}.namespace;
        key = key;
        cluster = clusterOf config.applications.${key};
        objects = (config.build._transformedObjects or { }).${key} or [ ];
      }) config.nixidy.publicApps;

      unresolved = check appsObjs;
    in
    if unresolved == [ ] then
      [ ]
    else
      let
        byApp = lib.groupBy (m: m.app) unresolved;
        bullets =
          ms:
          lib.concatMapStringsSep "\n" (
            m:
            "  - ${m.workload} references ${m.kind} `${m.name}` (namespace `${m.ns}`), which is not defined in this environment"
          ) ms;
        appNames = lib.attrNames byApp;
        message =
          if lib.length appNames == 1 then
            "unresolved resource references in application `${lib.head appNames}`:\n${
              bullets byApp.${lib.head appNames}
            }"
          else
            "unresolved resource references in this environment:\n"
            + lib.concatStringsSep "\n" (
              lib.mapAttrsToList (app: ms: "in application `${app}`:\n${bullets ms}") byApp
            );
      in
      [
        {
          assertion = false;
          message = message;
        }
      ]
  );
}
