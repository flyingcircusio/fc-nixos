{ lib, config, pkgs, ...}:

{

  options = {
    flyingcircus.raid.enable = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = "Enable management for RAID controllers";
    };
  };

  config = lib.mkIf config.flyingcircus.raid.enable {

    # Software RAID

    # Silence unused but broken-by-default mdmonitor
    # https://github.com/NixOS/nixpkgs/issues/72394
    systemd.services.mdmonitor.enable = false;

    flyingcircus.services.sensu-client.checks.raid_md = {
      notification = "RAID (md) status";
      command = "${pkgs.check_md_raid}/bin/check_md_raid";
    };

    # MegaRAID

    boot.initrd.kernelModules = [
        "megaraid_sas"
        "mpt3sas"
      ];

    environment.systemPackages = with pkgs; [
      megacli
      fc.megacli
    ];

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "${pkgs.check_megaraid}/bin/check_megaraid"
                     "${pkgs.fc.sensuplugins}/bin/check_megaraid_cache" ];
        groups = [ "sensuclient" ];
      }
    ];

    flyingcircus.services.sensu-client.checks.megaraid = {
      notification = "RAID (MegaRAID) status";
      command = "sudo ${pkgs.check_megaraid}/bin/check_megaraid";
    };

    flyingcircus.services.sensu-client.checks.megaraid_cache = {
      notification = "RAID (MegaRAID) cache status";
      command = "sudo ${pkgs.fc.sensuplugins}/bin/check_megaraid_cache -v -r -e 'MegaCli64 -LdPdInfo -aALL' -b 'MegaCli64 -AdpBbuCmd -GetBbuStatus -aALL' -W 50 -C 70";
    };

  };

}
