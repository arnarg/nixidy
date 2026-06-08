{ kubelib }:
rec {
  mkEnv =
    {
      pkgs,
      lib ? pkgs.lib,
      modules ? [ ],
      extraSpecialArgs ? { },
      charts ? { },
      libOverlay ? null,
    }:
    let
      generators = lib.getAttrs [
        "fromCRD"
        "fromCRDModule"
        "fromChartCRD"
        "fromChartCRDModule"
        "crdObjects"
        "crdObjectsFromChart"
      ] (import ./pkgs/generators { inherit pkgs kubelib; });
    in
    import ./modules {
      inherit
        pkgs
        lib
        extraSpecialArgs
        kubelib
        libOverlay
        ;
      modules = modules ++ [
        {
          _module.args.generators = lib.mkDefault generators;
          nixidy.charts = charts;
        }
      ];
    };

  mkEnvs =
    {
      pkgs,
      lib ? pkgs.lib,
      modules ? [ ],
      extraSpecialArgs ? { },
      envs ? { },
      charts ? { },
      libOverlay ? null,
    }:
    lib.mapAttrs (
      env: conf:
      mkEnv {
        inherit
          pkgs
          lib
          charts
          libOverlay
          ;
        extraSpecialArgs = extraSpecialArgs // (conf.extraSpecialArgs or { });
        modules = [
          {
            nixidy.env = lib.mkDefault env;
            nixidy.target.rootPath = lib.mkDefault "./manifests/${env}";
          }
        ]
        ++ modules
        ++ (conf.modules or [ ]);
      }
    ) envs;
}
