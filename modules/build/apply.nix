{ lib, pkgs }:
# Apply path + activation post-process emitters, both consuming the FileSpec
# layout seam (`config.build.layout`).
#
# Seam note: the post-process helpers `resolveCommand` and `chainOf` are shared
# between the apply path (which post-processes inline as it streams to `kubectl
# apply -f -`) and the activation path (which post-processes the staged tree in
# place). Both live here, in one file, so the shared chain logic is single-
# sourced. `mkApply` builds the declarative `apply` script;
# `mkActivationPostProcess` builds the activation post-process fragments (notice
# + per-file blocks) and the `anyRules` direct-vs-staged switch selector, which
# `emit-environment.nix`'s `mkActivation`
# splices into `activationPackage`. `emit-environment` therefore depends on this
# lib only for the already-rendered activation post-process bash, never on
# `chainOf`/`resolveCommand` directly.
rec {
  # Label prefix shared by the apply path's per-file selector labels.
  labelPrefix = "apps.nixidy.dev";

  # Resolve a rule's post-process command against a matched object: function-form
  # commands are applied to the resource; a literal snippet is used verbatim.
  # Shared by the activation block (compiles it to a script) and the up-front
  # notice (prints it), so what is shown is exactly what runs.
  resolveCommand =
    path: resource: r:
    if lib.isFunction r.postProcess.command then
      r.postProcess.command {
        inherit resource path pkgs;
        inherit (pkgs) lib;
      }
    else
      r.postProcess.command;

  # Build the `cmd1 | cmd2 | …` chain of writeShellApplication store paths for a
  # group's postProcess rules. `cmdPath` keys the script names and is the on-disk
  # path passed to function-form commands. Shared by the switch block and the
  # apply script.
  chainOf =
    cmdPath: resource: rules:
    let
      scriptOf =
        i: r:
        pkgs.writeShellApplication {
          name = "nixidy-post-process-${
            builtins.replaceStrings [ "/" "." ] [ "-" "-" ] cmdPath
          }-${toString i}";
          runtimeInputs = r.postProcess.runtimeInputs;
          # Verbatim command body; invoked by store path (no `sh -c` requote).
          text = resolveCommand cmdPath resource r;
        };
    in
    lib.concatMapStringsSep " | " (s: lib.getExe s) (lib.imap0 scriptOf rules);

  # The `rendered` FileSpecs across `applyAppNames`, in name order. `class`,
  # `rules` and `resource` come straight from the FileSpec (no head re-matching):
  # the strengthened multi-doc assertion guarantees a post-processed file is
  # single-object, so the FileSpec's `resource`/`rules` are exact.
  applyFilesOf =
    {
      layout,
      applyAppNames,
    }:
    lib.filter (s: s.source ? rendered) (lib.concatMap (n: layout.${n}) applyAppNames);

  # The declarative `apply` script body + the apply-path FileSpec list (exposed
  # for `build._applyFiles`/`build._applyScript` regression tests).
  mkApply =
    {
      env,
      layout,
      applyAppNames,
      environmentPackage,
    }:
    let
      applyFiles = applyFilesOf { inherit layout applyAppNames; };

      # Files whose chain runs at apply time (for the up-front notice/listing).
      applyChainFiles = lib.filter (f: f.rules != [ ]) applyFiles;

      applyPostProcessListing = pkgs.writeText "nixidy-apply-post-process-listing-${env}" (
        lib.concatMapStrings (
          f:
          "  ${f.path}:\n"
          + lib.concatMapStrings (
            r: "    ${lib.optionalString (r.name != null) "${r.name}: "}${resolveCommand f.path f.resource r}\n"
          ) f.rules
        ) applyChainFiles
      );

      # Up-front notice + TTY prompt. NOT gated on NIXIDY_SKIP_POST_PROCESS (apply
      # always post-processes). Runtime $ is heredoc-escaped (\''${…}, \$).
      applyPostProcessNotice = lib.optionalString (applyChainFiles != [ ]) ''
        echo "post-processing ${toString (lib.length applyChainFiles)} manifest file(s); the following commands run outside any sandbox. Review them before continuing:"
        cat ${applyPostProcessListing}
        if [ "\''${NIXIDY_POST_PROCESS_APPROVE:-}" != "1" ] && [ -t 0 ]; then
          printf 'Continue with post-processing? [y/N] '
          read -r _nixidy_pp_reply
          case "\$_nixidy_pp_reply" in
            [yY] | [yY][eE][sS]) ;;
            *)
              echo "aborted; nothing applied." >&2
              exit 1
              ;;
          esac
        fi
      '';

      # Per-file stream: clean environmentPackage file → add prune labels (BEFORE
      # the chain) → chain if the file has rules. yq labels every document.
      applyFileStream =
        f:
        let
          labelExpr = ''.metadata.labels."${labelPrefix}/application" = "${f.app}" | .metadata.labels."${labelPrefix}/${f.class}" = "${env}"'';
          labeled = ''cat "${environmentPackage}/${f.path}" | ${pkgs.yq-go}/bin/yq -P '${labelExpr}' '';
        in
        if f.rules == [ ] then labeled else "${labeled} | ${chainOf f.path f.resource f.rules}";

      applyClass =
        class: pruneAllowlist:
        let
          files = lib.filter (f: f.class == class) applyFiles;
          allowlistFlag = lib.optionalString (
            pruneAllowlist != null
          ) ''--prune-allowlist "${pruneAllowlist}"'';
          stream =
            if files == [ ] then
              "printf -- '---\\n'"
            else
              lib.concatMapStringsSep "\n        printf -- '---\\n'\n        " applyFileStream files;
        in
        ''
          echo "Applying ${class}"
          {
            ${stream}
          } | ${pkgs.kubectl}/bin/kubectl apply -f - \
            --prune --selector "${labelPrefix}/${class}=${env}" ${allowlistFlag}
        '';

      # The generated `apply` script body (consumes environmentPackage, runs
      # postProcess, streams to `kubectl apply -f -` per class).
      applyScript = ''
        #!/usr/bin/env bash
        set -eo pipefail

        ${applyPostProcessNotice}

        ${applyClass "crds" "apiextensions.k8s.io/v1/CustomResourceDefinition"}
        ${applyClass "namespaces" "core/v1/Namespace"}
        ${applyClass "manifests" null}
      '';

      package = pkgs.stdenv.mkDerivation {
        name = "nixidy-declarative-package-${env}";
        phases = [ "installPhase" ];
        installPhase = ''
          mkdir -p $out

          cat <<EOF > $out/apply
          ${applyScript}
          EOF

          chmod +x $out/apply
        '';
      };
    in
    {
      inherit applyFiles applyScript package;
    };

  # Per-app map: on-disk relative path -> { resource; rules; }, derived from the
  # layout's post-processed FileSpecs. Equivalent to the old per-object
  # `filePostProcesses`: the strengthened single-object assertion makes the
  # FileSpec's `resource`/`rules` exactly the per-object entry, and `spec.path`
  # equals the old `objPath app obj`.
  filePostProcessesOf =
    specs:
    lib.listToAttrs (
      map (s: lib.nameValuePair s.path { inherit (s) resource rules; }) (
        lib.filter (s: s.rules != [ ]) specs
      )
    );

  # Activation post-process fragments + the direct-vs-staged switch selector,
  # consumed by `emit-environment.nix`'s `activationPackage`.
  #   - allFilePostProcesses : path -> { resource; rules; } across all apps
  #   - anyRules             : true iff any FileSpec across all apps has rules
  #   - postProcessNotice    : up-front notice (gated on NIXIDY_SKIP_POST_PROCESS)
  #   - postProcessBlocks    : per-file in-place rewrite blocks
  mkActivationPostProcess =
    {
      env,
      layout,
    }:
    let
      # Flatten every app's filePostProcesses into a single { path -> { resource;
      # rules; } } map. Within an app the uniqueness assertion guarantees no path
      # collisions; across apps paths are prefixed by each app's distinct
      # `app.output.path`, so they cannot collide either.
      allFilePostProcesses = lib.foldl' (acc: specs: acc // filePostProcessesOf specs) { } (
        lib.attrValues layout
      );

      # Activation post-process block for a single (path, rules) entry: rewrite
      # the staged file in place via the chained rule commands, honoring
      # NIXIDY_SKIP_POST_PROCESS.
      postProcessBlock =
        path:
        { resource, rules }:
        let
          chain = chainOf path resource rules;
          # Named rules in the chain, for the activation log.
          ruleNames = lib.filter (n: n != null) (map (r: r.name) rules);
          label = path + lib.optionalString (ruleNames != [ ]) " (${lib.concatStringsSep ", " ruleNames})";
        in
        ''
          if [ "\''${NIXIDY_SKIP_POST_PROCESS:-}" = "1" ]; then
            mkdir -p "\$(dirname "\$staging/${path}")"
            if [ -f "\$dest/${path}" ]; then
              cp "\$dest/${path}" "\$staging/${path}"
            else
              rm -f "\$staging/${path}"
            fi
          else
            echo "Post-processing ${label}"
            mkdir -p "\$(dirname "\$staging/${path}")"
            TARGET_PATH="\$dest/${path}" ${chain} \
              < "\$staging/${path}" > "\$staging/${path}.tmp" \
              && mv "\$staging/${path}.tmp" "\$staging/${path}"
          fi
        '';

      postProcessBlocks = lib.concatStringsSep "\n" (
        lib.mapAttrsToList postProcessBlock allFilePostProcesses
      );

      # Up-front activation notice: print every post-process command about to run,
      # against which file, once before any command executes. These commands run
      # outside any sandbox, so this is visibility (not a gate) for the "switching
      # to someone else's config is code execution" case. Showing the actual
      # command (not just a rule name) is the honest signal for a due-diligence
      # bail. Rendered to a store file and `cat`ed so arbitrary command text needs
      # no heredoc escaping. Skipped under NIXIDY_SKIP_POST_PROCESS, where nothing
      # runs.
      postProcessListing = pkgs.writeText "nixidy-post-process-listing-${env}" (
        lib.concatStrings (
          lib.mapAttrsToList (
            path:
            { resource, rules }:
            "  ${path}:\n"
            + lib.concatMapStrings (
              r: "    ${lib.optionalString (r.name != null) "${r.name}: "}${resolveCommand path resource r}\n"
            ) rules
          ) allFilePostProcesses
        )
      );

      postProcessNotice =
        let
          fileCount = lib.length (lib.attrNames allFilePostProcesses);
        in
        ''
          if [ "\''${NIXIDY_SKIP_POST_PROCESS:-}" != "1" ]; then
            echo "post-processing ${toString fileCount} manifest file(s); the following commands run outside any sandbox. Review them before continuing:"
            cat ${postProcessListing}
            # Pause for confirmation only when stdin is a terminal: a piped/CI/
            # pre-commit run is non-interactive and proceeds untouched, so
            # automation never blocks. NIXIDY_POST_PROCESS_APPROVE=1 skips the prompt
            # for trusted, repeated interactive use. This is informed-consent UX, not
            # a security boundary (the config defining the rule can set the approval
            # variable too); the point is to surface an unsandboxed postProcess
            # command to a human switching to a config they have not vetted.
            if [ "\''${NIXIDY_POST_PROCESS_APPROVE:-}" != "1" ] && [ -t 0 ]; then
              printf 'Continue with post-processing? [y/N] '
              read -r _nixidy_pp_reply
              case "\$_nixidy_pp_reply" in
                [yY] | [yY][eE][sS]) ;;
                *)
                  echo "aborted; no changes written." >&2
                  exit 1
                  ;;
              esac
            fi
          fi
        '';
    in
    {
      inherit allFilePostProcesses postProcessBlocks postProcessNotice;
      anyRules = allFilePostProcesses != { };
    };
}
