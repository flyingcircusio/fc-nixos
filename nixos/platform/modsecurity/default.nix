{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.flyingcircus.modsecurity;

  mkModsecurityConfig =
    rules:
    (import ./mk-modsecurity-config.nix) {
      inherit lib pkgs rules;
    };

  rulesetOptionsModule = {
    options = import ./modsecurity-options.nix {
      inherit config lib pkgs;
    };
  };

  rulesetImplModule =
    { config, name, ... }:
    {
      options = with lib; {
        nginxMode = mkOption {
          type = (
            types.enum [
              "On"
              "Off"
              "Transparent"
            ]
          );
          default = "Transparent";
        };

        transactionID = mkOption {
          type = types.str;
          default = "$request_id";
        };

        configContent = mkOption {
          type = types.str;
          internal = true;
        };

        rulesFile = mkOption {
          type = types.path;
          internal = true;
        };

        nginxConfig = mkOption {
          type = types.str;
        };

        mkNginxConfig = mkOption {
          internal = true;
        };
      };

      config = {
        configContent = mkModsecurityConfig config;
        rulesFile = pkgs.writeText name config.configContent;
        nginxConfig = config.mkNginxConfig config.nginxMode "";
        mkNginxConfig =
          nginxMode: extraConfig:
          lib.concatStringsSep ";\n" [
            (lib.optionalString (nginxMode != "Transparent") "modsecurity ${(lib.toSentenceCase nginxMode)}")
            "modsecurity_rules_file ${config.rulesFile}"
            "modsecurity_transaction_id ${config.transactionID}"
            extraConfig
          ];
      };
    };

  nginxIntegrationSubmodule =
    { config, name, ... }:
    {
      config = lib.mkIf cfg.enable {
        extraConfig = lib.mkBefore (
          lib.optionalString (lib.hasAttr name cfg.rulesets) cfg.rulesets.${name}.nginxConfig
        );
      };
    };

in
{
  options = with lib; {
    flyingcircus.modsecurity = {

      enable = mkEnableOption { };

      rulesets = mkOption {
        type =
          with lib.types;
          lazyAttrsOf (submodule [
            rulesetOptionsModule
            rulesetImplModule
          ]);
        default = { };
      };
    };

    services.nginx.virtualHosts = mkOption {
      type = types.attrsOf (types.submodule nginxIntegrationSubmodule);
    };

  };

}
