{
  pkgs,
  lib ? pkgs.lib,
}:
let
  #########
  ## K8s ##
  #########
  fromSchema =
    name: schema:
    import ./generator.nix {
      inherit
        pkgs
        lib
        name
        schema
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

  genRoots =
    with lib;
    swagger: namespaced:
    let
      refType = attr: head (tail (tail (splitString "/" attr."$ref")));

      refDefinition = attr: head (tail (tail (splitString "/" attr."$ref")));

      mapCharPairs =
        f: s1: s2:
        concatStrings (
          imap0 (i: c1: f i c1 (if i >= stringLength s2 then "" else elemAt (stringToCharacters s2) i)) (
            stringToCharacters s1
          )
        );

      getAttrName =
        resource: kind:
        mapCharPairs (
          i: c1: c2:
          if lib.hasPrefix "API" kind && i == 0 then
            "A"
          else if i == 0 then
            c1
          else if c2 == "" || (lib.toLower c2) != c1 then
            c1
          else
            c2
        ) resource kind;
    in
    mapAttrs'
      (
        name: path:
        let
          ref = refType (head path.post.parameters).schema;
          name' = last (splitString "/" name);
          group' = path.post."x-kubernetes-group-version-kind".group;
          group = if group' == "" then "core" else group';
          version = path.post."x-kubernetes-group-version-kind".version;
          kind = path.post."x-kubernetes-group-version-kind".kind;
          attrName = getAttrName name' kind;
        in
        nameValuePair ref {
          inherit
            ref
            attrName
            group
            version
            kind
            ;
          inherit (swagger.definitions.${ref}) description;

          name = name';
          definition = refDefinition (head path.post.parameters).schema;
          namespaced = attrByPath [ group version kind ] false namespaced;
        }
      )
      (
        filterAttrs (
          _name: path: hasAttr "post" path && path.post."x-kubernetes-action" == "post"
        ) swagger.paths
      );

  k8s = pkgs.linkFarm "k8s-generated" (
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

          swagger = builtins.fromJSON (builtins.readFile "${src}/${conf.spec}");

          schema = {
            inherit (swagger) definitions;
            roots = genRoots swagger namespaced;
          };
        in
        {
          name = "v${short}.nix";
          path = fromSchema "v${short}" schema;
        }
      ) (import ./versions.nix)
    )
  );

  #########
  ## CRD ##
  #########
  fromCRD =
    {
      name,
      src,
      crds,
      namePrefix ? "",
      attrNameOverrides ? { },
    }:
    let
      options = pkgs.writeText "${name}-crd2jsonschema-options.json" (
        builtins.toJSON {
          inherit crds namePrefix attrNameOverrides;
        }
      );

      # The nix code generator is slightly modified from kubenix's
      # generator. As it kind of depends on the jsonschema to be
      # flattened with `$ref`s we first pre-process the CRD with
      # a crude python script to flatten it before running the
      # generator.
      # See: crd2jsonschema.py
      schema =
        let
          pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
        in
        pkgs.stdenv.mkDerivation {
          inherit src;

          name = "${name}-jsonschema.json";

          phases = [
            "unpackPhase"
            "installPhase"
          ];

          installPhase = ''
            ${pythonWithYaml}/bin/python ${./crd2jsonschema.py} "${options}" > $out
          '';
        };
    in
    import ./generator.nix {
      inherit
        pkgs
        lib
        name
        ;

      schema = builtins.fromJSON (builtins.readFile schema);
    };
in
{
  inherit fromCRD k8s;

  argocd = fromCRD {
    name = "argocd";
    src = pkgs.fetchFromGitHub {
      owner = "argoproj";
      repo = "argo-cd";
      rev = "v3.0.0";
      hash = "sha256-g401mpNEhCNe8H6lk2HToAEZlZa16Py8ozK2z5/UozA=";
    };
    crds = [
      "manifests/crds/application-crd.yaml"
      "manifests/crds/applicationset-crd.yaml"
      "manifests/crds/appproject-crd.yaml"
    ];
  };
}
