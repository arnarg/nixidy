{ lib }:
# Pure layout core: turns each nixidy application into a list of FileSpec (one
# per output file), the seam every build emitter consumes via `config.build.layout`.
rec {
  # Eval-time rewrite, env rules then app rules.
  applyRewrites =
    rules: objs:
    let
      rewrites = lib.filter (r: r.rewrite != null) rules;
    in
    lib.concatMap (
      obj:
      let
        out = lib.foldl' (
          o: r:
          if o == null then
            null
          else if r.predicate o then
            r.rewrite o
          else
            o
        ) obj rewrites;
      in
      lib.optional (out != null) out
    ) objs;

  transformedObjects =
    envRules: app: applyRewrites app.objectTransforms (applyRewrites envRules app.objects);

  # File class for --prune selectors.
  classify =
    obj:
    if obj.kind == "CustomResourceDefinition" then
      "crds"
    else if obj.kind == "Namespace" then
      "namespaces"
    else
      "manifests";

  # Per-app FileSpec list. `objectBaseName` is applications/lib.nix's
  # filename-stem helper (the on-disk group key).
  mkAppFiles =
    {
      envRules,
      objectBaseName,
    }:
    app:
    let
      allRules = envRules ++ app.objectTransforms;
      postProcessRulesFor = obj: lib.filter (r: r.postProcess != null && r.predicate obj) allRules;

      grouped = builtins.groupBy objectBaseName (transformedObjects envRules app);

      renderedSpecs = lib.mapAttrsToList (
        groupKey: objs:
        let
          sorted = lib.sort (a: b: (a.metadata.namespace or "") < (b.metadata.namespace or "")) objs;
          matched = lib.filter (o: postProcessRulesFor o != [ ]) objs;
          # The strengthened assertion (build.nix) guarantees a post-processed
          # group is single-object, so this matched-head == the group head; we
          # carry the matched object so `resource` is the rule's actual target.
          resource = if matched == [ ] then null else builtins.head matched;
        in
        {
          app = app.name;
          path = "${app.output.path}/${groupKey}.yaml";
          source.rendered = sorted;
          class = classify (builtins.head objs);
          rules = if resource == null then [ ] else postProcessRulesFor resource;
          inherit resource;
        }
      ) grouped;

      rawSpecs = map (src: {
        app = app.name;
        path = "${app.output.path}/${baseNameOf src}";
        source.rawFile = src;
        class = null;
        rules = [ ];
        resource = null;
      }) app.extraRawYamls;
    in
    renderedSpecs ++ rawSpecs;
}
