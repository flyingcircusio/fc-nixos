# Configure systemd journal access and local units.
{ config, lib, pkgs, ... }:

with lib;
{
  config = {

    services.journald.extraConfig = ''
      SystemMaxUse=1G
      MaxLevelConsole=notice
      ForwardToSyslog=true
    '';

    system.activationScripts.systemd-journal-acl = ''
      # Ensure journal access for all users.
      chmod -R a+rX /var/log/journal
    '';

    system.activationScripts.systemd-local = ''
      install -d -o root -g service -m 02775 /etc/local/systemd
    '';

    systemd.extraConfig = ''
      DefaultRestartSec=3
      DefaultStartLimitInterval=60
      DefaultStartLimitBurst=3
    '';

    systemd.units =
      let
        unit_files = if (builtins.pathExists "/etc/local/systemd")
          then config.fclib.filesRel "/etc/local/systemd" else [];
        unit_configs = map
          (file: { "${file}" =
             { text = readFile ("/etc/local/systemd/" + file);
               wantedBy = [ "multi-user.target" ];};})
          unit_files;
      in zipAttrsWith (name: values: (last values)) unit_configs;

  };
}
