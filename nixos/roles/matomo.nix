{ config, lib, pkgs, ... }:

with builtins;

let
  inherit (config) fclib;
  cfg = config.flyingcircus.roles.matomo;
  serviceCfg = config.services.matomo;

  inherit (serviceCfg.tools) matomoCheckPermissions matomoConsole;

  currentMemory = fclib.currentMemory 1024;

  phpFpmMemoryLimit = fclib.min [ (currentMemory * 25 / 100) 1024 ];
in
{
  options = with lib; {
    flyingcircus.roles.matomo = {
      enable = mkEnableOption "Matomo Web Analytics";

      supportsContainers = fclib.mkEnableContainerSupport;

      hostname = mkOption {
        type = types.str;
        default = fclib.fqdn { vlan = "fe"; };
        description = ''
          Public FQDN for the Matomo Web UI.
          A Letsencrypt certificate is generated for it.
          Defaults to the FE FQDN.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    flyingcircus.services.nginx.enable = true;

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [
          "${serviceCfg.tools.matomoConsole}/bin/matomo-console"
          "/run/current-system/sw/bin/matomo-console"
        ];
        users = [ "sensuclient" ];
        groups = [ "service" "sudo-srv" ];
        runAs = "matomo";
      }
      {
        commands = [
          "/run/current-system/sw/bin/matomo-check-permissions"
          "/run/current-system/sw/bin/stat /var/lib/matomo/share/config/config.ini.php"
          "${serviceCfg.tools.matomoCheckPermissions}/bin/matomo-check-permissions"
          "${pkgs.coreutils}/bin/stat /var/lib/matomo/share/config/config.ini.php"
        ];
        users = [ "sensuclient" ];
        groups = ["service" ];
      }
    ];

    flyingcircus.services.sensu-client.checks = {

      matomo-config = {
        notification = "Config file cannot be read.";
        command = ''
          if ! sudo -u matomo stat /var/lib/matomo/share/config/config.ini.php; then
            echo "config.ini.php not found, is Matomo installed?"
            exit 1
          fi
        '';
      };
      matomo-permissions = {
        notification = "Matomo permissions are wrong";
        command = ''
          sudo ${matomoCheckPermissions}/bin/matomo-check-permissions
        '';
      };

      matomo-unexpected-files = {
        notification = "Found unexpected files in the Matomo webroot dir.";
        command = ''
          sudo -u matomo ${matomoConsole}/bin/matomo-console diagnostics:unexpected-files \
            && echo "OK, no unexpected files found in Matomo installation."
        '';
      };

      matomo-version = {
        notification = "Cannot get Matomo version via matomo-console.";
        command = ''
          sudo -u matomo ${matomoConsole}/bin/matomo-console core:version
        '';
      };
    };

    services.matomo = {
      inherit (cfg) hostname;
      enable = true;
      memoryLimit = fclib.mkPlatform phpFpmMemoryLimit;
      nginx = {
        listenAddresses = fclib.network.fe.dualstack.addressesQuoted;
      };
      periodicArchiveProcessing = true;
    };
  };

}
