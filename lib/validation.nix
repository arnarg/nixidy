# Pure cross-resource reference validation logic. Walks workload pod
# specs for references to ConfigMaps, Secrets, PVCs and ServiceAccounts
# and reports unresolved ones; free of the module system so it can be
# unit-tested in isolation (see lib/tests.nix).
{ lib, ... }:
let
  # Built-in workload kinds (objects containing a pod spec) and where
  # their pod spec lives. Users extend this table with their own CRDs
  # (e.g. `Rollout`) via `nixidy.validation.references.workloads`.
  defaultWorkloads = {
    Pod.podSpecPath = [ "spec" ];
    Deployment.podSpecPath = [
      "spec"
      "template"
      "spec"
    ];
    StatefulSet.podSpecPath = [
      "spec"
      "template"
      "spec"
    ];
    DaemonSet.podSpecPath = [
      "spec"
      "template"
      "spec"
    ];
    ReplicaSet.podSpecPath = [
      "spec"
      "template"
      "spec"
    ];
    Job.podSpecPath = [
      "spec"
      "template"
      "spec"
    ];
    CronJob.podSpecPath = [
      "spec"
      "jobTemplate"
      "spec"
      "template"
      "spec"
    ];
  };

  # Resources the cluster auto-creates in every namespace; never unresolved.
  systemRefs = [
    {
      kind = "ConfigMap";
      name = "kube-root-ca.crt";
    }
    {
      kind = "ServiceAccount";
      name = "default";
    }
  ];

  isSystemRef = r: lib.any (s: s.kind == r.kind && s.name == r.name) systemRefs;

  # Tolerate missing/non-list fields where k8s expects a list.
  orList = v: if builtins.isList v then v else [ ];

  # Safe nested attribute lookup; null when any hop is missing or not an attrset.
  pick =
    obj: path:
    builtins.foldl' (
      a: p: if a != null && builtins.isAttrs a && a ? ${p} then a.${p} else null
    ) obj path;

  # A reference record carrying the manifest field path it came from, or
  # null when the name is missing/empty/non-string.
  namedRef =
    kind: path: name: optional:
    if name == null || name == "" || !builtins.isString name then
      null
    else
      {
        inherit kind name path;
        optional = lib.isBool optional && optional;
      };

  # Like namedRef but from a selector attrset ({ name; optional; }).
  selRef =
    kind: path: sel:
    if sel == null || !builtins.isAttrs sel then
      null
    else
      namedRef kind path (sel.name or null) (sel.optional or false);

  # fnmatch-style glob (`*`) translated to a regex; `.` stays literal.
  globToRegex = pat: lib.concatMapStringsSep ".*" lib.escapeRegex (lib.splitString "*" pat);

  # Objects without an explicit namespace land in the app's namespace.
  effectiveNamespace =
    app: obj:
    let
      ns = obj.metadata.namespace or null;
    in
    if ns == null || ns == "" then app.namespace else ns;

  # Path (inside the object) where the pod spec lives for each workload kind.
  podSpecPrefix = workloads: kind: lib.concatStringsSep "." (workloads.${kind}.podSpecPath or [ ]);

  # The pod spec of a workload object, or { } when absent.
  podSpecOf =
    workloads: kind: obj:
    let
      walk =
        obj: path:
        builtins.foldl' (
          a: p: if a != null && builtins.isAttrs a && a ? ${p} then a.${p} else { }
        ) obj path;
    in
    walk obj (workloads.${kind}.podSpecPath or [ ]);

  # All references reachable from one pod spec, each tagged with its
  # manifest field path (built from PREFIX).
  refsFromPodSpec =
    prefix: ps:
    let
      # configMap/secret/PVC volumes, plus projected source volumes.
      volumeRefs =
        lib.concatMap
          (
            iv:
            let
              i = iv.index;
              v = iv.value;
              proj =
                lib.imap0
                  (j: s: [
                    (selRef "ConfigMap"
                      "${prefix}.volumes[${toString i}].projected.sources[${toString j}].configMap.name"
                      (pick s [ "configMap" ])
                    )
                    (selRef "Secret" "${prefix}.volumes[${toString i}].projected.sources[${toString j}].secret.name" (
                      pick s [ "secret" ]
                    ))
                  ])
                  (
                    orList (
                      pick v [
                        "projected"
                        "sources"
                      ]
                    )
                  );
            in
            lib.filter (r: r != null) (
              [
                (namedRef "ConfigMap" "${prefix}.volumes[${toString i}].configMap.name"
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
                (namedRef "Secret" "${prefix}.volumes[${toString i}].secret.secretName"
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
                (namedRef "PersistentVolumeClaim" "${prefix}.volumes[${toString i}].persistentVolumeClaim.claimName"
                  (pick v [
                    "persistentVolumeClaim"
                    "claimName"
                  ])
                  null
                )
              ]
              ++ lib.concatLists proj
            )
          )
          (
            lib.imap0 (i: v: {
              index = i;
              value = v;
            }) (orList (pick ps [ "volumes" ]))
          );

      # envFrom and env valueFrom references for one container class
      # (cls is the field name: containers/initContainers/ephemeralContainers).
      containerRefs =
        cls: containers:
        lib.concatMap
          (
            ic:
            let
              i = ic.index;
              c = ic.value;
              envFromRefs = lib.imap0 (j: e: [
                (selRef "ConfigMap" "${prefix}.${cls}[${toString i}].envFrom[${toString j}].configMapRef.name" (
                  pick e [ "configMapRef" ]
                ))
                (selRef "Secret" "${prefix}.${cls}[${toString i}].envFrom[${toString j}].secretRef.name" (
                  pick e [ "secretRef" ]
                ))
              ]) (orList (pick c [ "envFrom" ]));
              envRefs = lib.imap0 (j: e: [
                (selRef "ConfigMap"
                  "${prefix}.${cls}[${toString i}].env[${toString j}].valueFrom.configMapKeyRef.name"
                  (
                    pick e [
                      "valueFrom"
                      "configMapKeyRef"
                    ]
                  )
                )
                (selRef "Secret" "${prefix}.${cls}[${toString i}].env[${toString j}].valueFrom.secretKeyRef.name" (
                  pick e [
                    "valueFrom"
                    "secretKeyRef"
                  ]
                ))
              ]) (orList (pick c [ "env" ]));
            in
            lib.filter (r: r != null) (lib.concatLists envFromRefs ++ lib.concatLists envRefs)
          )
          (
            lib.imap0 (i: v: {
              index = i;
              value = v;
            }) containers
          );

      # Image pull secrets are always Secret references.
      pullRefs = lib.filter (r: r != null) (
        lib.imap0 (i: s: selRef "Secret" "${prefix}.imagePullSecrets[${toString i}].name" s) (
          orList (pick ps [ "imagePullSecrets" ])
        )
      );
    in
    # Drop nulls and system resources (auto-created by the cluster), then
    # add the pod's serviceAccountName reference.
    lib.filter (r: r != null && !(isSystemRef r)) (
      volumeRefs
      ++ containerRefs "containers" (orList (pick ps [ "containers" ]))
      ++ containerRefs "initContainers" (orList (pick ps [ "initContainers" ]))
      ++ pullRefs
      ++ containerRefs "ephemeralContainers" (orList (pick ps [ "ephemeralContainers" ]))
      ++ [
        (namedRef "ServiceAccount" "${prefix}.serviceAccountName" (pick ps [ "serviceAccountName" ]) null)
      ]
    );

  # Built-in generator rules mapping CRD kinds to the resources they
  # generate in-cluster, keyed by generated kind then generator kind.
  # Users extend this table via `nixidy.validation.references.generators`.
  defaultGenerators = {
    Secret = {
      Certificate.namePath = [
        "spec"
        "secretName"
      ];
      ExternalSecret.namePath = [
        "spec"
        "target"
        "name"
      ];
      SealedSecret.namePath = [
        "spec"
        "template"
        "metadata"
        "name"
      ];
      OnePasswordItem = { };
    };
  };

  # Definitions implicitly created by a CRD object (e.g. a cert-manager
  # Certificate generating a Secret): GENERATORS maps generated kind ->
  # generator kind -> { namePath; }; for each rule whose generator kind
  # matches the object's kind, yield the generated resource's name.
  generatedDefinitions =
    generators: obj:
    lib.concatMap (
      generatedKind:
      lib.concatMap (
        generatorKind:
        let
          g = generators.${generatedKind}.${generatorKind};
          picked = if (g.namePath or [ ]) == [ ] then null else pick obj g.namePath;
          fallback =
            let
              n = obj.metadata.name or null;
            in
            if n == null then "" else n;
          name = if picked != null && builtins.isString picked && picked != "" then picked else fallback;
        in
        if generatorKind != (obj.kind or "") then
          [ ]
        else
          lib.optionals (name != "") [
            {
              kind = generatedKind;
              inherit name;
            }
          ]
      ) (lib.attrNames generators.${generatedKind})
    ) (lib.attrNames generators);

  # Unresolved-reference candidates for a single workload object; optional
  # references are skipped (they may legitimately not exist). Objects whose
  # kind is not registered in WORKLOADS are not walked.
  objectRefs =
    workloads: app: obj:
    let
      kind = obj.kind or "";
    in
    if !(workloads ? ${kind}) then
      [ ]
    else
      let
        prefix = podSpecPrefix workloads kind;
        ps = podSpecOf workloads kind obj;
        ns = effectiveNamespace app obj;
        workloadName =
          let
            n = obj.metadata.name or null;
          in
          if n == null || n == "" then
            (
              let
                g = obj.metadata.generateName or null;
              in
              if g == null || g == "" then "<unnamed>" else g
            )
          else
            n;
        refs = lib.filter (r: r != null && !r.optional && r.name != "") (refsFromPodSpec prefix ps);
      in
      map (r: {
        app = app.name;
        appKey = app.key;
        workloadKind = kind;
        inherit workloadName;
        kind = r.kind;
        name = r.name;
        path = r.path;
        inherit ns;
        cluster = app.cluster;
      }) refs;
in
{
  inherit
    defaultWorkloads
    defaultGenerators
    systemRefs
    globToRegex
    effectiveNamespace
    podSpecOf
    refsFromPodSpec
    objectRefs
    generatedDefinitions
    ;

  globMatches = pat: value: (builtins.match (globToRegex pat) value) != null;

  # Cluster identity an app targets: destination name if set, else server.
  clusterOf =
    app:
    if app.destination.name != null then
      app.destination.name
    else if app.destination.server != null then
      app.destination.server
    else
      "";

  # Check all references in appsObjs against the definitions of every app
  # in the same environment, honouring ignore rules; returns the unresolved
  # references that remain. Only object kinds registered in WORKLOADS are
  # walked for pod-spec references.
  checkReferences =
    {
      appsObjs,
      ignore ? [ ],
      generators ? defaultGenerators,
      workloads ? defaultWorkloads,
    }:
    let
      # Resource kinds that only count as defined when explicitly declared.
      defKinds = [
        "ConfigMap"
        "Secret"
        "PersistentVolumeClaim"
        "ServiceAccount"
      ];

      # Everything that provides a definition, keyed cluster|kind|name|ns:
      # declared objects, StatefulSet volumeClaimTemplates (implicit PVCs)
      # and resources generated by CRD objects.
      defs = builtins.listToAttrs (
        map (d: lib.nameValuePair "${d.cluster}|${d.kind}|${d.name}|${d.ns}" true) (
          lib.concatMap (
            app:
            lib.concatMap (
              obj:
              let
                kind = obj.kind or "";
                ns = effectiveNamespace app obj;
                direct = lib.optionals (lib.elem kind defKinds) [
                  {
                    cluster = app.cluster;
                    inherit kind;
                    name =
                      let
                        n = obj.metadata.name or null;
                      in
                      if n == null then "" else n;
                    inherit ns;
                  }
                ];
                # volumeClaimTemplates define PVCs at runtime; count as defs.
                volumeClaimTemplates = lib.optionals (kind == "StatefulSet") (
                  map
                    (t: {
                      cluster = app.cluster;
                      kind = "PersistentVolumeClaim";
                      name =
                        let
                          n = t.metadata.name or null;
                        in
                        if n == null then "" else n;
                      inherit ns;
                    })
                    (
                      orList (
                        pick obj [
                          "spec"
                          "volumeClaimTemplates"
                        ]
                      )
                    )
                );
              in
              direct
              ++ volumeClaimTemplates
              ++ map (d: {
                cluster = app.cluster;
                kind = d.kind;
                inherit (d) name;
                inherit ns;
              }) (generatedDefinitions generators obj)
            ) app.objects
          ) appsObjs
        )
      );

      allRefs = lib.concatMap (app: lib.concatMap (objectRefs workloads app) app.objects) appsObjs;

      # A reference is unresolved when nothing defines its
      # cluster|kind|name|ns combination.
      missing = lib.filter (r: !(defs ? "${r.cluster}|${r.kind}|${r.name}|${r.ns}")) allRefs;

      # Ignore rules: scope by app (name or key) and kind, glob the name.
      isExcluded =
        r:
        lib.any (
          e:
          (e.app == null || e.app == r.app || e.app == r.appKey)
          && (e.kind == null || e.kind == r.kind)
          && (builtins.match (globToRegex e.name) r.name) != null
        ) ignore;
    in
    lib.filter (r: !(isExcluded r)) missing;
}
