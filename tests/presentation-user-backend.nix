# Third-party extensibility proof: a presentation backend defined PURELY from
# ordinary user config via `nixidy.presentation.backends.<name>` — no edit to any
# nixidy module — is selected and rendered end-to-end, with its own per-app option
# and zero coupling to the built-in argocd/flux backends.
#
# The custom backend registers `perAppOptions` (declaring `applications.<name>.custom.field`)
# and a `present` that emits one raw object per public app onto the `__custom`
# synthetic app (`__`-prefixed, so `publicApps` excludes it — same pattern as flux's
# `__flux-system`). `typeImports` is empty, so no CRD type is imported.
{ lib, config, ... }:
let
  # The full dispatched result (present ctx spliced into `applications`), so the
  # assertions below prove the backend rendered via the real dispatcher — not just
  # that its `present` function returns the right shape in isolation.
  customObjects = config.applications.__custom.objects;
in
{
  # A presentation backend contributed entirely from user config — the registry
  # entry is the whole integration surface.
  nixidy.presentation.backends.custom = {
    # Declares `applications.<name>.custom.field`, threaded into the applications
    # submodule type only while this backend is selected.
    perAppOptions = [
      (
        { lib, ... }:
        {
          options.custom.field = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Arbitrary per-app value carried by the custom backend.";
          };
        }
      )
    ];

    # One raw controller object per public app, reading that app's `custom.field`.
    # `__custom` is `__`-prefixed so it never presents itself.
    present = ctx: {
      __custom.objects = map (name: {
        apiVersion = "example.com/v1";
        kind = "CustomApp";
        metadata.name = name;
        spec.field = ctx.apps.${name}.custom.field;
      }) ctx.publicApps;
    };
  };

  nixidy.presentation.backend = "custom";

  applications.myapp1 = {
    namespace = "ns1";
    custom.field = "alpha";
    resources.configMaps.cm.data.x = "y";
  };
  applications.myapp2 = {
    namespace = "ns2";
    custom.field = "beta";
    resources.configMaps.cm.data.a = "b";
  };

  test = {
    name = "user-provided backend extensibility";
    description = "a backend registered purely from user config (custom per-app option + present) renders end-to-end and stays isolated from argocd/flux";
    assertions = [
      # (a) the custom per-app option is readable on the resolved application.
      {
        description = "custom per-app option is readable on config.applications.<name>.custom.field";
        expression = {
          myapp1 = config.applications.myapp1.custom.field;
          myapp2 = config.applications.myapp2.custom.field;
        };
        assertion = v: v.myapp1 == "alpha" && v.myapp2 == "beta";
      }

      # (b) the custom controller objects render via the dispatcher: one object per
      # public app, each carrying that app's custom field.
      {
        description = "__custom.objects carries one CustomApp per public app, each with its custom.field";
        expression = {
          byName = lib.listToAttrs (map (o: lib.nameValuePair o.metadata.name o) customObjects);
          publicApps = lib.sort (a: b: a < b) config.nixidy.publicApps;
        };
        assertion =
          v:
          v.publicApps == [
            "myapp1"
            "myapp2"
          ]
          && lib.all (o: o.apiVersion == "example.com/v1" && o.kind == "CustomApp") (lib.attrValues v.byName)
          && (v.byName.myapp1.spec.field or null) == "alpha"
          && (v.byName.myapp2.spec.field or null) == "beta";
      }

      # (c) ISOLATION: under backend=custom, no argocd per-app options are threaded.
      {
        description = "no argocd per-app coupling: config.applications.<name> has no `argocd` attr";
        expression = config.applications.myapp1 ? argocd;
        expected = false;
      }
      # ISOLATION: no argocd app-of-apps and no flux `__flux-system` synthetic app.
      {
        description = "no argocd app-of-apps and no __flux-system synthetic app exist";
        expression = {
          hasAppOfApps = config.applications ? ${config.nixidy.presentation.argocd.name};
          hasFluxSystem = config.applications ? __flux-system;
        };
        assertion = v: !v.hasAppOfApps && !v.hasFluxSystem;
      }
      # ISOLATION: custom's `typeImports` is empty, so no argocd `Application` CRD
      # type is imported (nothing threaded into applicationImports for this backend).
      {
        description = "custom backend imports no resource types (typeImports empty)";
        expression = config.nixidy.presentation.backends.custom.typeImports;
        expected = [ ];
      }
    ];
  };
}
