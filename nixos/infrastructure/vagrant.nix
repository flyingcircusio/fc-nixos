{ config, lib, ... }:

{

  imports = if (builtins.pathExists /etc/nixos/vagrant.nix) then [
  	/etc/nixos/vagrant.nix
  ] else [];

  config = lib.mkIf (config.flyingcircus.infrastructureModule == "vagrant") {
  	# Partially copied from generic virtualbox image.

    boot.growPartition = lib.mkDefault true;
    boot.loader.grub.device = lib.mkDefault "/dev/sda";

    fileSystems."/" = lib.mkOverride 90 {
      fsType = "xfs";
      device = "/dev/disk/by-label/nixos";
    };

    flyingcircus.agent.enable = false;

    services.timesyncd.servers = [ "pool.ntp.org" ];

    virtualisation.virtualbox.guest.enable = lib.mkDefault true;
    zramSwap.enable = true;

    # Vagrant box protocol
    users.users.root.password = "vagrant";

    # The login group gets created through the ENC normally which
    # doesn't exist in vagrant or at least here, yet.
    users.groups.login = {};
    users.groups.service = {};

    users.users.vagrant = {
    	description = "Vagrant user";
    	group = "users";
    	extraGroups = [ "login" "service" ];
    	password = "vagrant";
    	home = "/home/vagrant";
    	isNormalUser = true;
    	openssh.authorizedKeys.keys = [
	    	"ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key"
	    ];
	};

    security.sudo = {
      extraRules = lib.mkBefore [
        # Allow unrestricted access to vagrant
        {
          commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ];
          users = [ "vagrant" ];
        }
      ];
    };

    # General vagrant optimizations

    networking.firewall.enable = false;

    services.openssh.extraConfig = ''
      UseDNS no
    '';

    swapDevices = [ { device = "/var/swapfile";
                      size = 2048; }];

  };
}
