{
  modules,
  pkgs,
  kubelib,
  lib ? pkgs.lib,
  extraSpecialArgs ? { },
  libOverlay ? null,
}:
let
  extendedLib = import ../lib { inherit pkgs kubelib; };

  nixidyModules = import ./modules.nix;

  module = lib.evalModules {
    modules = modules ++ [ ./templates.nix ] ++ nixidyModules;
    specialArgs = {
      inherit pkgs;
      lib = if builtins.isFunction libOverlay then extendedLib.extend libOverlay else extendedLib;
    }
    // extraSpecialArgs;
  };

  allAssertions =
    module.config.nixidy.assertions
    ++ lib.concatMap (name: module.config.applications.${name}.assertions) (
      builtins.attrNames module.config.applications
    );

  failed = lib.filter (a: !a.assertion) allAssertions;

  formatFailed =
    assertions:
    "failed assertions:\n"
    + (lib.concatMapStringsSep "\n" (a: "- assertion(${a.context}): ${a.message}") assertions);

  allWarnings = lib.filter (warning: warning.when) (
    module.config.nixidy.warnings
    ++ lib.concatMap (name: module.config.applications.${name}.warnings) (
      builtins.attrNames module.config.applications
    )
  );

  traceIfWarnings =
    ret:
    if allWarnings != [ ] then
      builtins.trace (
        "warnings:\n"
        + (lib.concatMapStringsSep "\n" (w: "- warning(${w.context}): ${w.message}") allWarnings)
      ) ret
    else
      ret;

  checkedBuildOutputs = lib.throwIf (failed != [ ]) (formatFailed failed) (traceIfWarnings {
    inherit (module.config.build)
      environmentPackage
      activationPackage
      bootstrapPackage
      declarativePackage
      ;
  });

  # Get all available resource roots for the environment.
  # Here we use the `__bootstrap` application to access
  # them as it's guaranteed to exist.
  resourceTypeRoots = map (t: {
    inherit (t)
      group
      version
      kind
      attrName
      ;
  }) (builtins.attrValues module.config.applications.__bootstrap.types);

  # Walks down into resource options by path which is a
  # list of strings.
  drillOption =
    path: opt:
    if path == [ ] then
      opt
    else
      let
        name = builtins.head path;
        rest = builtins.tail path;
        subOpts =
          if opt ? type && lib.isFunction (opt.type.getSubOptions or null) then
            opt.type.getSubOptions (opt.loc or [ ])
          else
            { };
        child = subOpts.${name} or null;
      in
      if lib.isOption child then drillOption rest child else null;

  getTypeInfo = type: {
    name = type.name or "unspecified";
    description = type.description or type.name or "unspecified";
  };

  roots =
    (module.options.applications.type.getSubOptions [
      "applications"
      "<name>"
    ]).resources or { };

  # Producces a JSON serializable object for a single option.
  walkOption =
    path: opt:
    let
      description = opt.description or "";
      typeInfo = getTypeInfo opt.type;
      subOpts =
        if opt ? type && lib.isFunction (opt.type.getSubOptions or null) then
          let
            so = opt.type.getSubOptions (opt.loc or path);
          in
          if lib.isAttrs so && so != { } then lib.filterAttrs (_: lib.isOption) so else null
        else
          null;
    in
    {
      inherit description;
      type = typeInfo;
    }
    // lib.optionalAttrs (subOpts != null) {
      children = lib.mapAttrs (name: _: {
        description = subOpts.${name}.description or "";
        type = getTypeInfo subOpts.${name}.type;
      }) (builtins.removeAttrs subOpts [ "_priority" ]);
    };

  # Takes an attrName for a resource root and a dot-path
  # down into the resource and build a JSON serializable
  # snapshot with description, type and children.
  explainResource =
    attrName: dotPath:
    let
      path = if dotPath == "" then [ ] else lib.splitString "." dotPath;
      baseOpt = roots.${attrName} or null;
      target = if lib.isOption baseOpt then drillOption path baseOpt else null;
      displayPath = [
        "resources"
        attrName
      ]
      ++ path;
    in
    if target != null then walkOption displayPath target else null;

  # Recursively walks option sub-options building a nested
  # attrset with description, type and children at each level.
  # This is used by the devenv builder which can't use --apply.
  walkOptionTree =
    path: opt:
    let
      typeInfo = getTypeInfo opt.type;
      subOpts =
        if opt ? type && lib.isFunction (opt.type.getSubOptions or null) then
          let
            so = opt.type.getSubOptions (opt.loc or path);
          in
          if lib.isAttrs so && so != { } then lib.filterAttrs (_: lib.isOption) so else null
        else
          null;
    in
    {
      description = opt.description or "";
      type = typeInfo;
    }
    // lib.optionalAttrs (subOpts != null) {
      children = lib.mapAttrs (childName: childOpt: walkOptionTree (path ++ [ childName ]) childOpt) (
        builtins.removeAttrs subOpts [ "_priority" ]
      );
    };
in
{
  inherit (module) config;
  inherit (checkedBuildOutputs)
    environmentPackage
    activationPackage
    bootstrapPackage
    declarativePackage
    ;
  meta = { inherit (module.config.nixidy.target) repository branch; };
  resources = {
    roots = resourceTypeRoots;
    explain = explainResource;
    options = lib.mapAttrs (name: baseOpt: walkOptionTree [ "resources" name ] baseOpt) (
      lib.filterAttrs (_: lib.isOption) roots
    );
  };
}
