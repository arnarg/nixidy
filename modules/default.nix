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

  # Wrap every output build package in an assertion and warning check.
  # This is done so they can't be accessed without checking for failed
  # assertions and print warnings.
  checkedBuildOutputs =
    let
      # Collect all failed assertions, both from global and application
      # scope.
      failedAssertions = lib.filter (a: !a.assertion) (
        module.config.nixidy.assertions
        ++ lib.concatMap (name: module.config.applications.${name}.assertions) (
          builtins.attrNames module.config.applications
        )
      );

      # Collect all warnings, both from global and application scope.
      allWarnings = lib.filter (warning: warning.when) (
        module.config.nixidy.warnings
        ++ lib.concatMap (name: module.config.applications.${name}.warnings) (
          builtins.attrNames module.config.applications
        )
      );

      # Fail the build if there are failed assertions.
      failIfAssertions =
        failed: ret:
        let
          # Format a list of failed assertions.
          failMessage =
            "failed assertions:\n"
            + (lib.concatMapStringsSep "\n" (a: "- assertion(${a.context}): ${a.message}") failed);
        in
        lib.throwIf (failed != [ ]) failMessage ret;

      # Prints a list of warnings if there are any.
      traceIfWarnings =
        warnings: ret:
        if warnings != [ ] then
          builtins.trace (
            "warnings:\n" + (lib.concatMapStringsSep "\n" (w: "- warning(${w.context}): ${w.message}") warnings)
          ) ret
        else
          ret;

      assertionCheckWrapper =
        failed: warnings: output:
        failIfAssertions failed (traceIfWarnings warnings output);
    in
    assertionCheckWrapper failedAssertions allWarnings {
      inherit (module.config.build)
        environmentPackage
        activationPackage
        bootstrapPackage
        declarativePackage
        ;
    };

  # Declare information and utils for `nixidy resources` sub-command.
  resources =
    let
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

      # Extracts a JSON serializable summary of an option type.
      getTypeInfo = type: {
        name = type.name or "unspecified";
        description = type.description or type.name or "unspecified";
      };

      # Returns the sub-options of an option as a filtered attrset,
      # or null if it has none.
      getSubOpts =
        path: opt:
        if opt ? type && lib.isFunction (opt.type.getSubOptions or null) then
          let
            so = opt.type.getSubOptions (opt.loc or path);
          in
          if lib.isAttrs so && so != { } then lib.filterAttrs (_: lib.isOption) so else null
        else
          null;

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
            subOpts = getSubOpts [ ] opt;
            child = if subOpts != null then subOpts.${name} or null else null;
          in
          if lib.isOption child then drillOption rest child else null;

      # The resource option tree exposed by the applications module,
      # used as the entry point for option introspection.
      resourceOptions =
        (module.options.applications.type.getSubOptions [
          "applications"
          "<name>"
        ]).resources or { };

      # Shared body for describing a single option: returns description,
      # type info and (if present) its children mapped via `childMapper`.
      describeOption =
        childMapper: path: opt:
        let
          subOpts = getSubOpts path opt;
        in
        {
          description = opt.description or "";
          type = getTypeInfo opt.type;
        }
        // lib.optionalAttrs (subOpts != null) {
          children = lib.mapAttrs childMapper (builtins.removeAttrs subOpts [ "_priority" ]);
        };

      # Produces a JSON serializable object for a single option.
      walkOption =
        path: opt:
        describeOption (_: childOpt: {
          description = childOpt.description or "";
          type = getTypeInfo childOpt.type;
        }) path opt;

      # Recursively walks option sub-options building a nested
      # attrset with description, type and children at each level.
      # This is used by the devenv builder which can't use --apply.
      walkOptionTree =
        path: opt: describeOption (name: childOpt: walkOptionTree (path ++ [ name ]) childOpt) path opt;

      # Takes an attrName for a resource root and a dot-path
      # down into the resource and build a JSON serializable
      # snapshot with description, type and children.
      explainResource =
        attrName: dotPath:
        let
          path = if dotPath == "" then [ ] else lib.splitString "." dotPath;
          baseOpt = resourceOptions.${attrName} or null;
          target = if lib.isOption baseOpt then drillOption path baseOpt else null;
          displayPath = [
            "resources"
            attrName
          ]
          ++ path;
        in
        if target != null then walkOption displayPath target else null;
    in
    {
      roots = resourceTypeRoots;
      explain = explainResource;
      options = lib.mapAttrs (name: baseOpt: walkOptionTree [ "resources" name ] baseOpt) (
        lib.filterAttrs (_: lib.isOption) resourceOptions
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
  inherit resources;
  meta = { inherit (module.config.nixidy.target) repository branch; };
}
