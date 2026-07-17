{ lib, pkgs }:
# Environment-side emitters: the per-app render derivation (`renderApp`) and the
# four packages built from it — `environmentPackage`, `activationPackage`,
# `bootstrapPackage`, `extrasPackage`. All consume the FileSpec layout seam
# (`config.build.layout`) plus `render.nix`'s `renderFile`.
#
# Seam note: the activation post-process logic (the chained rule commands and
# the up-front notice) lives in `apply.nix` because it shares `chainOf`/
# `resolveCommand` with the apply path. `mkActivation` receives those already-
# rendered bash fragments via the `postProcess` argument and splices them in;
# this lib never touches `chainOf` directly. The direct-vs-staged switch keys
# off `postProcess.anyRules` (= any FileSpec across all apps has `rules != []`),
# preserving the old `allFilePostProcesses == {}` test.
let
  # Per-app render derivation: fold `render.renderFile` over the app's FileSpecs.
  renderApp =
    {
      layout,
      renderFile,
    }:
    app:
    let
      specs = layout.${app.name};

      writeManifests = ''
        set -e
        out=$1

      ''
      + lib.concatStringsSep "\n" (map (renderFile app.output.path) specs);
    in
    pkgs.stdenv.mkDerivation {
      inherit writeManifests;
      name = "nixidy-app-${app.name}";
      passAsFile = [ "writeManifests" ];
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out
        sh $writeManifestsPath $out
      '';
    };
in
{
  # linkFarm of `config.nixidy.extraFiles` (e.g. `.revision`). These are file
  # data, not FileSpecs, and stay outside the seam.
  mkExtras =
    {
      env,
      extraFiles,
    }:
    pkgs.linkFarm "nixidy-extras-${env}" (
      lib.mapAttrsToList (_: file: {
        name = file.path;
        path = file.source;
      }) extraFiles
    );

  # The `__bootstrap` app's render derivation (the appOfApps manifest).
  mkBootstrap =
    {
      layout,
      renderFile,
      bootstrapApp,
    }:
    renderApp { inherit layout renderFile; } bootstrapApp;

  # linkFarm of all public apps' render derivations mounted at each
  # `app.output.path`, joined with `extrasPackage` via `symlinkJoin`. The app
  # subset is `publicApps` (all non-`__` apps — includes the appOfApps app).
  mkEnvironment =
    {
      env,
      layout,
      renderFile,
      publicApps,
      extrasPackage,
    }:
    let
      joined = pkgs.linkFarm "nixidy-apps-joined-${env}" (
        map (app: {
          name = app.output.path;
          path = renderApp { inherit layout renderFile; } app;
        }) publicApps
      );
    in
    pkgs.symlinkJoin {
      name = "nixidy-environment-${env}";
      paths = [
        joined
        extrasPackage
      ];
    };

  # The `activate` script. Direct-vs-staged switch selected by
  # `postProcess.anyRules`. The staged branch splices in `postProcess`'s
  # already-rendered notice + per-file blocks (from `apply.nix`'s
  # `mkActivation`). Preserves the `.revision`-excluded rsync diff fast path.
  mkActivation =
    {
      env,
      environmentPackage,
      rootPath,
      postProcess,
    }:
    pkgs.stdenv.mkDerivation {
      name = "nixidy-activation-environment-${env}";
      phases = [ "installPhase" ];

      installPhase =
        let
          rsyncFlags = "--chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r --recursive --delete --copy-links";

          # No post-process rules: sync the built environment straight to the
          # target, skipping all work when nothing changed (excluding .revision,
          # which churns through CI and would otherwise loop).
          directSwitch = ''
            if ! ${pkgs.diffutils}/bin/diff -q -r --exclude .revision "${environmentPackage}" "\$dest" &>/dev/null; then
              echo "switching manifests"
              ${pkgs.rsync}/bin/rsync ${rsyncFlags} "${environmentPackage}/" "\$dest"
              echo "done!"
            else
              echo "no changes!"
            fi
          '';

          # Post-process rules present: stage the environment, run the rules over
          # the matched files, then sync the staging tree to the target.
          # NIXIDY_SKIP_POST_PROCESS=1 preserves the existing post-processed
          # target files (re-use what is on disk instead of re-processing).
          stagedSwitch = ''
            echo "switching manifests"

            ${postProcess.postProcessNotice}

            staging=\$(mktemp -d)
            trap 'rm -rf "\$staging"' EXIT
            cp -rL --no-preserve=mode "${environmentPackage}"/. "\$staging"/

            ${postProcess.postProcessBlocks}

            ${pkgs.rsync}/bin/rsync ${rsyncFlags} "\$staging/" "\$dest"

            echo "done!"
          '';
        in
        ''
          mkdir -p $out

          ln -s ${environmentPackage} $out/environment

          cat <<EOF > $out/activate
          #!/usr/bin/env bash
          set -eo pipefail
          dest="${rootPath}"

          mkdir -p "\$dest"

          ${if postProcess.anyRules then stagedSwitch else directSwitch}
          EOF

          chmod +x $out/activate
        '';
    };
}
