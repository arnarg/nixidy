{ lib }:
let
  inherit (builtins)
    removeAttrs
    filter
    map
    head
    tail
    isList
    isAttrs
    hasAttr
    getAttr
    concatMap
    attrValues
    ;
  inherit (lib) mapAttrsToList;
in
# Pure layout core: turns each nixidy application into a list of FileSpec (one
# per output file), the seam every build emitter consumes via `config.build.layout`.
rec {
  withResourceFromPath =
    path: f: obj:
    let
      withAttrs =
        attr: f: obj:
        if hasAttr attr obj then
          let
            value = f (getAttr attr obj);
          in
          if value == null then removeAttrs obj [ attr ] else obj // { ${attr} = value; }
        else
          obj;
      withList = f: objs: filter (v: v != null) (map f objs);
    in
    if isList obj then
      withList (withResourceFromPath path f) obj
    else if path != [ ] then
      withAttrs (head path) (withResourceFromPath (tail path) f) obj
    else
      f obj;

  applyTransform =
    transform: resource:
    withResourceFromPath transform.path (
      obj:
      if obj == null then
        null
      else if transform.predicate obj then
        if transform.transforms != null then
          lib.pipe obj (map applyTransform (attrValues transform.transforms))
        else if transform.update != null then
          lib.recursiveUpdate obj (transform.update obj)
        else if transform.replace == null then
          null
        else
          transform.replace obj
      else
        obj
    ) resource;

  # Eval-time rewrite, env rules then app rules.
  applyTransforms =
    rules: objs:
    let
      optionalTransform =
        transform: obj: filter (v: v != null) (lib.toList (applyTransform transform obj));
      # Apply a transform over all objs, then merge the results.
      # This means that if `value` returns a list, it can generate
      # multiple resources in place of a single one.
      applyRule =
        _: rule: objs:
        concatMap (optionalTransform rule) objs;
    in
    # This applies each transform to the objs in sequence,
    # so that if multiple resoruces are returned from a `value`,
    # they can be processed by further transforms.
    lib.pipe objs (mapAttrsToList applyRule rules);

  transformedObjects =
    envObjectTransforms: app:
    applyTransforms app.objectTransforms (applyTransforms envObjectTransforms app.objects);

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
      envObjectTransforms,
      envPostProcessors,
      objectBaseName,
    }:
    app:
    let
      allPostProcessors = (attrValues envPostProcessors) ++ (attrValues app.postProcessors);
      postProcessRulesFor = obj: lib.filter (r: r.predicate obj) allPostProcessors;

      grouped = builtins.groupBy objectBaseName (transformedObjects envObjectTransforms app);

      renderedSpecs = lib.mapAttrsToList (
        groupKey: objs:
        let
          sorted = lib.sort (a: b: (a.metadata.namespace or "") < (b.metadata.namespace or "")) objs;
          matched = lib.filter (o: postProcessRulesFor o != [ ]) objs;
          # The strengthened assertion (default.nix) guarantees a post-processed
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
