{ config, lib, ... }:

with builtins;

let
  expandLocal = dirs:
  listToAttrs (
    map (dir: (
      lib.nameValuePair dir {
        dir = "/etc/local/${dir}"; permissions = "02775"; group = "service"; }))
      dirs);

in {

  imports = if (pathExists /etc/nixos/vagrant.nix) then [
    /etc/nixos/vagrant.nix
  ] else [];

  config = lib.mkIf (config.flyingcircus.infrastructureModule == "vagrant") {

    # Partially copied from generic virtualbox image
    boot.growPartition = lib.mkDefault true;
    boot.loader.grub.device = lib.mkDefault "/dev/sda";

    fileSystems."/" = lib.mkOverride 90 {
      fsType = "xfs";
      device = "/dev/disk/by-label/nixos";
    };

    services.timesyncd.servers = [ "pool.ntp.org" ];

    virtualisation.virtualbox.guest.enable = lib.mkDefault true;
    zramSwap.enable = true;

    # Vagrant box protocol
    users.users.root.password = "vagrant";

    # We expect some groups in our platform code.
    # These groups are created through the ENC normally which
    # doesn't exist in vagrant or at least here, yet.
    users.groups = {
      login = { members = ["vagrant"]; };
      service = { members = ["vagrant"]; };
      sudo-srv = {};
      admins = {};
    };

    users.users.vagrant = {
      description = "Vagrant user";
      group = "users";
      extraGroups = [ "docker" ];
      # password: vagrant
      hashedPassword = "$5$xS9kX8R5VNC0g$ZS7QkUYTk/61dUyUgq9r0jLAX1NbiScBT5v1PODz4UC";
      home = "/home/vagrant";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key"
      ];
    };

    users.users.s-test = {
      description = "A service user for deployment testing";
      home = "/srv/s-test/";
      isNormalUser = true;
      extraGroups = [ "service" ];
    };

    # General vagrant optimizations
    networking.firewall.enable = false;
    services.openssh.extraConfig = "UseDNS no";
    swapDevices = [ { device = "/var/swapfile"; size = 2048; }];

    # FC specific customizations
    flyingcircus = {
      agent.enable = false;

      localConfigDirs = {
        logrotate-vagrant = {
          user = "vagrant";
          dir = "/etc/local/logrotate/vagrant";
        };
      } // expandLocal [ "nixos" "sensu-client" "telegraf" ];

      passwordlessSudoRules = [
        { # Grant unrestricted access to vagrant
          commands = [ "ALL" ];
          users = [ "vagrant" ];
        }
      ];
    };

    system.activationScripts.relaxHomePermissions = lib.stringAfter [] ''
      chmod 755 /home/*
    '';
  };
}
