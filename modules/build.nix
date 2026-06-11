{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (config.nixidy) env;

  helpers = import ./applications/lib.nix lib;

  # Pure layout core: per-app [FileSpec] seam.
  layoutLib = import ./build/layout.nix { inherit lib; };
  layout = lib.mapAttrs (
    _: app:
    layoutLib.mkAppFiles {
      envRules = config.nixidy.objectTransforms;
      objectBaseName = helpers.objectBaseName;
    } app
  ) config.applications;

  # FileSpec -> shell fragment.
  render = import ./build/render.nix { inherit lib pkgs; };

  # Environment-side emitters (environment/activation/bootstrap/extras + mkApp).
  emitEnv = import ./build/emit-environment.nix { inherit lib pkgs; };

  # Apply path + activation post-process emitters.
  applyLib = import ./build/apply.nix { inherit lib pkgs; };

  # App-name subsets the emitters draw from.
  #   publicAppNames : every non-`__` app (includes the appOfApps app).
  #   applyAppNames  : publicApps minus the appOfApps app (the declarative set).
  publicAppNames = config.nixidy.publicApps;
  applyAppNames = lib.filter (n: n != config.nixidy.appOfApps.name) publicAppNames;

  # Apply emitter result (declarative package + apply script + apply files) and
  # the activation post-process fragments shared with `activationPackage`.
  apply = applyLib.mkApply {
    inherit env layout applyAppNames;
    environmentPackage = config.build.environmentPackage;
  };
  activationPostProcess = applyLib.mkActivationPostProcess {
    inherit env layout;
  };
in
{
  options = with lib; {
    build = {
      bootstrapPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing the bootstrap appOfApps application manifest.";
      };
      extrasPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing all the extra files for an environment.";
      };
      environmentPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing all the applications for an environment.";
      };
      activationPackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing all the applications and an activation script.";
      };
      declarativePackage = mkOption {
        type = types.package;
        internal = true;
        description = "The package containing manifests meant to be deployed directly using `kubectl apply --prune`.";
      };
      layout = mkOption {
        internal = true;
        readOnly = true;
        type = types.attrsOf (types.listOf types.attrs);
        default = layout;
        description = "Internal: per-application [FileSpec] layout seam (for tests and emitters).";
      };
      _transformedObjects = mkOption {
        internal = true;
        readOnly = true;
        type = types.attrsOf (types.listOf types.attrs);
        default = lib.mapAttrs (
          _: app: layoutLib.transformedObjects config.nixidy.objectTransforms app
        ) config.applications;
        description = "Internal: per-application objects after eval-time rewrite transforms (for tests).";
      };
      _filePostProcesses = mkOption {
        internal = true;
        readOnly = true;
        type = types.attrsOf (types.attrsOf types.anything);
        default = lib.mapAttrs (_: specs: applyLib.filePostProcessesOf specs) config.build.layout;
        description = "Internal: per-app output-path -> { resource; rules; } (for tests).";
      };
      _applyFiles = mkOption {
        internal = true;
        readOnly = true;
        type = types.listOf types.attrs;
        default = apply.applyFiles;
      };
      _applyScript = mkOption {
        internal = true;
        readOnly = true;
        type = types.str;
        default = apply.applyScript;
        description = "Internal: the generated `apply` script body (for tests).";
      };
    };
  };

  config = {
    # A post-processed file must be single-object: for every FileSpec, having
    # post-process `rules` implies its `rendered` group holds exactly one object.
    # This strengthens the old group-key-collision check (it also rejects a
    # non-head object post-processed in a multi-object group), guaranteeing the
    # head-based FileSpec is exact and apply == activation by construction.
    # Emitted as a single env-scope assertion naming the offending app + path.
    nixidy.assertions =
      let
        bad = lib.filter (s: s.rules != [ ] && lib.length (s.source.rendered or [ ]) != 1) (
          lib.concatLists (lib.attrValues config.build.layout)
        );
      in
      [
        {
          assertion = bad == [ ];
          message =
            "objectTransforms postProcess rule targets a multi-document file in application(s): "
            + lib.concatMapStringsSep ", " (s: "`${s.app}` (${s.path})") bad
            + "; post-processing a multi-document file is undefined.";
        }
      ];

    build = {
      bootstrapPackage = emitEnv.mkBootstrap {
        inherit layout;
        renderFile = render.renderFile;
        bootstrapApp = config.applications.__bootstrap;
      };

      extrasPackage = emitEnv.mkExtras {
        inherit env;
        extraFiles = config.nixidy.extraFiles;
      };

      environmentPackage = emitEnv.mkEnvironment {
        inherit env layout;
        renderFile = render.renderFile;
        publicApps = map (name: config.applications.${name}) publicAppNames;
        extrasPackage = config.build.extrasPackage;
      };

      activationPackage = emitEnv.mkActivation {
        inherit env;
        environmentPackage = config.build.environmentPackage;
        rootPath = config.nixidy.target.rootPath;
        postProcess = activationPostProcess;
      };

      declarativePackage = apply.package;
    };
  };
}
