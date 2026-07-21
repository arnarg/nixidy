# Guards modules/nixidy/extra-files.nix's `bootstrap.yaml` emission, which is
# gated behind `nixidy.bootstrapManifest.enable` (default off, so no other test
# exercises it). The bootstrap filename is backend-owned: the argocd backend
# names it `Application-<appOfApps.name>.yaml`. Also covers the top-level
# appOfApps `name` alias (set via the OLD `nixidy.appOfApps.name` path).
{ lib, config, ... }:
{
  nixidy.bootstrapManifest.enable = true;
  nixidy.appOfApps.name = "rootapp"; # OLD path (aliased to presentation.argocd.name)

  applications.test.resources.namespaces.test1 = { };

  test = with lib; {
    name = "bootstrap-manifest";
    description = "bootstrapManifest emits bootstrap.yaml with the backend-owned manifest filename.";
    assertions = [
      {
        description = "appOfApps.name alias forwards to presentation.argocd.name";
        expression = config.nixidy.presentation.argocd.name;
        assertion = v: v == "rootapp";
      }
      {
        description = "backend provides the bootstrap manifest filename";
        expression = config.nixidy.presentation.bootstrapManifestFile;
        assertion = v: v == "Application-rootapp.yaml";
      }
      {
        description = "bootstrap.yaml source points at the backend-named manifest in bootstrapPackage";
        expression = config.nixidy.extraFiles."bootstrap.yaml".source;
        assertion = src: lib.hasSuffix "/Application-rootapp.yaml" "${src}";
      }
    ];
  };
}
