{ pkgs, lib, config, ... }:

with lib;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.beats;

  resourceGroupLoghosts =
    fclib.listServiceAddresses "graylog-server" ++
    fclib.listServiceAddresses "loghost-server";

  loghostsToUse = lib.unique (
    # Pick one of the resource group loghosts or a graylog from the cluster...
    (if (length resourceGroupLoghosts > 0) then
      [(head resourceGroupLoghosts)] else []) ++

    # ... and always add the central location loghost (if it exists).
    (fclib.listServiceAddresses "loghost-location-server"));
in
{
  options.flyingcircus.beats = {
    logTargets = mkOption {
      type = with types; attrsOf (submodule {
        options = {
          host = mkOption { type = str; };
          port = mkOption { type = int; };
        };
      });
      description = ''
        Where beats should send the messages,
        using the logstash output.
        This can be Graylog instances with Beats input, for example.
        By default, send logs to a resource group loghost if present
        and a central one.
      '';
    };

    fields = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Additional fields that are added to each log message.
        They appear as field_<name> in the log message.
      '';
     };
  };

  config.flyingcircus.beats.logTargets =
    lib.listToAttrs
      (map (l: lib.nameValuePair l { host = l; port = 12301; })
      loghostsToUse);
}
