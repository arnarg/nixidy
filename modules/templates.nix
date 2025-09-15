{
  lib,
  config,
  ...
}:
let
  # Templates are implemented by creating an application import
  # for each template.
  # This function turns a template name, options and `output` function
  # into a module that can be imported with `applicationImports`.
  mkImportable =
    name: opts: func:
    { config, ... }@args:
    let
      mod = {
        options = opts;
      };
    in
    {
      options = with lib; {
        templates."${name}" = mkOption {
          type = with lib.types; attrsOf (submodule mod);
          default = { };
        };
      };

      config = {
        resources =
          with lib;
          mkMerge (
            mapAttrsToList (
              n: v:
              func (
                args
                // {
                  name = n;
                  config = v;
                }
              )
            ) config.templates."${name}"
          );
      };
    };

  tmplMod =
    { config, ... }:
    {
      options = with lib; {
        options =
          let
            optType = mkOptionType {
              name = "option";
              description = "option";
              descriptionClass = "noun";
              check = isOption;
              merge = mergeEqualOption;
            };
            recOptType = with lib.types; either optType (attrsOf recOptType);
          in
          mkOption {
            type = with lib.types; attrsOf recOptType;
          };
        output = mkOption {
          type = with lib.types; functionTo (attrsOf anything);
        };
      };
    };
in
{
  options.templates = lib.mkOption {
    type = with lib.types; attrsOf (submodule tmplMod);
    default = { };
  };

  config = {
    nixidy.applicationImports = lib.mapAttrsToList (
      name: val: mkImportable name val.options val.output
    ) config.templates;
  };
}
