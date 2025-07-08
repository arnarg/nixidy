{kubelib}: rec {
  mkEnv = {
    pkgs,
    env,
    lib ? pkgs.lib,
    modules ? [],
    extraSpecialArgs ? {},
    charts ? {},
    libOverlay ? null,
  }:
    import ./modules {
      inherit pkgs lib kubelib libOverlay;
      extraSpecialArgs = extraSpecialArgs // {inherit env;};
      modules =
        modules
        ++ [
          {
            nixidy.charts = charts;
          }
        ];
    };

  mkEnvs = {
    pkgs,
    lib ? pkgs.lib,
    modules ? [],
    extraSpecialArgs ? {},
    envs ? {},
    charts ? {},
    libOverlay ? null,
  }:
    lib.mapAttrs (
      env: conf:
        mkEnv {
          inherit pkgs lib charts libOverlay env;
          extraSpecialArgs = extraSpecialArgs // (conf.extraSpecialArgs or {});
          modules =
            [{nixidy.target.rootPath = lib.mkDefault "./manifests/${env}";}]
            ++ modules
            ++ (conf.modules or []);
        }
    )
    envs;
}
