{
  mkConfig,
  mkService,
  beatName, # journalbeat
  beatData, # log messages from the journal
  extraSettings ? {},
}:
{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.flyingcircus.beats;
in
{
  config = let
    _extra = extraSettings // { inherit (config.flyingcircus.${beatName}) fields; };
  in
  {
    systemd.services = mapAttrs' (name: value: nameValuePair "${beatName}-${name}" (let
      extra = _extra // value.extraSettings;
    in mkService {
      inherit (value) host port;
      inherit (config.flyingcircus.${beatName}) fields package;
      inherit name extra;

      config = pkgs.writeText "${beatName}-${name}.json"
        (generators.toJSON {} (mkConfig {
          inherit (value) host port;
          inherit name extra;
          inherit (config.flyingcircus.${beatName}) fields package;
        }));
    })) (config.flyingcircus.${beatName}.logTargets);

    flyingcircus.${beatName} = {
      fields = cfg.fields;
      logTargets = cfg.logTargets;
    };
  };

  options = {
    flyingcircus.${beatName} = {
      fields = mkOption {
        type = types.attrs;
        default = {};
        description = ''
          Additional fields that are added to each log message.
          They appear as field_<name> in the log message.
        '';
       };

      logTargets = mkOption {
        type = with types; attrsOf (submodule {
          options = {
            host = mkOption { type = str; };
            port = mkOption { type = int; };
            extraSettings = mkOption { type = attrs; default = {}; };
          };
        });
        default = {};
        # default = cfg.logTargets;
        description = ''
          Where ${beatName} should send ${beatData},
          using the logstash output.
          This can be Graylog instances with Beats input, for example.
          By default, send logs to a resource group loghost if present
          and a central one.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs."${beatName}7";
        defaultText = "pkgs.${beatName}7";
        example = literalExample "pkgs.${beatName}7";
        description = ''
          The ${beatName} package to use.
        '';
      };

    };
  };
}
