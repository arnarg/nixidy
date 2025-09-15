{
  pkgs,
  lib,
}:
let
  fromSpec =
    name: spec: namespaced:
    import ./k8s.nix {
      inherit
        pkgs
        lib
        name
        spec
        namespaced
        ;
    };

  genNamespaced =
    core: aggregated:
    let
      core' =
        let
          data = builtins.fromJSON (builtins.readFile core);
        in
        {
          core = {
            ${data.groupVersion} = lib.mergeAttrsList (
              lib.concatMap (
                res:
                lib.optional (res.singularName != "") {
                  ${res.kind} = res.namespaced;
                }
              ) data.resources
            );
          };
        };

      aggregated' =
        let
          data = builtins.fromJSON (builtins.readFile aggregated);
        in
        lib.mergeAttrsList (
          map (item: {
            ${item.metadata.name} = lib.mergeAttrsList (
              map (version: {
                ${version.version} = lib.mergeAttrsList (
                  map (res: {
                    ${res.responseKind.kind} = res.scope == "Namespaced";
                  }) version.resources
                );
              }) item.versions
            );
          }) data.items
        );
    in
    core' // aggregated';
in
pkgs.linkFarm "k8s-generated" (
  builtins.attrValues (
    builtins.mapAttrs (
      version: conf:
      let
        short = builtins.concatStringsSep "." (lib.lists.sublist 0 2 (builtins.splitVersion version));

        src = pkgs.fetchFromGitHub {
          owner = "kubernetes";
          repo = "kubernetes";
          rev = "v${version}";
          hash = conf.hash;
        };

        namespaced = genNamespaced "${src}/${conf.discovery.core}" "${src}/${conf.discovery.aggregated}";
      in
      {
        name = "v${short}.nix";
        path = fromSpec "v${short}" "${src}/${conf.spec}" namespaced;
      }
    ) (import ./versions.nix)
  )
)
