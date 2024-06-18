{
  lib,
  config,
  ...
}: {
  options = with lib; {
    applications = mkOption {
      type = with types;
        attrsOf (submoduleWith {
          modules = [./applications] ++ config.nixidy.resourceImports;
          specialArgs.nixidyDefaults = config.nixidy.defaults;
        });
      default = {};
      description = ''
        An application is a single Argo CD application that will be rendered by nixidy.

        The resources will be rendered into it's own directory and an Argo CD application created for it.
      '';
      example = {
        nginx = {
          namespace = "nginx";
          resources = {
            deployments.nginx.spec = {
              replicas = 3;
              selector.matchLabels.app = "nginx";
              template = {
                metadata.labels.app = "nginx";
                spec = {
                  securityContext.fsGroup = 1000;
                  containers.nginx = {
                    image = "nginx:1.25.1";
                    imagePullPolicy = "IfNotPresent";
                  };
                };
              };
            };

            services.nginx.spec = {
              selector.app = "nginx";
              ports.http.port = 80;
            };
          };
        };
      };
    };

    nixidy.resourceImports = mkOption {
      type = with types; listOf (oneOf [package path (functionTo attrs)]);
      default = [];
      description = "List of modules to import for resource defintion options.";
    };
  };
}
