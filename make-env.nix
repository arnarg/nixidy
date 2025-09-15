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
