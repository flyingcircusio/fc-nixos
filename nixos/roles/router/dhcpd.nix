{ config, lib, ...}:

with builtins;

let
  role = config.flyingcircus.roles.router;
  inherit (config) fclib;
  inherit (config.flyingcircus) location;
  inherit (config.networking) hostName;
  suffix = "gocept.net";
  baseConf = ''
    # Common DHCP configuration options (AF-agnostic)
    ddns-update-style none;
    log-facility daemon;
    default-lease-time 1800;
    max-lease-time 7200;
    option domain-name "${suffix}";
    option domain-search "${suffix}", "${location}.${suffix}";
    option ntp-servers ${hostName};
  '';

  # from static.nameservers.${location}
  # Includes dev-router virt IP4
  resolvers = config.networking.nameservers;

  resolvers6 = [
    "2a02:238:f030:1c2::1" # dev-router virt IP6
    "2a02:238:f030:1c3::4" # ?
    "2a02:238:f030:1c3::1087" # ?
  ];

  dhcpd4Conf = ''
    # DHCPv4 specific general options
    option domain-name-servers ${lib.concatStringsSep ", " resolvers};

    if exists user-class and option user-class = "iPXE" {
        # We are currently running iPXE: load the static boot script.
        filename "flyingcircus.ipxe";
    } else {
        # We are currently running the built-in ROM PXE and switch to boot the
        # iPXE kernel.
        filename "undionly.kpxe"; # we are in burned in PXE and load iPXE kernel
    }
    next-server ${location}-router.${suffix};
    '';

  local4Conf = fclib.configFromFile "/etc/nixos/localconfig-dhcpd4.conf" "";

  dhcpd6Conf = ''
    # DHCPv6 specific general options
    option dhcp6.name-servers ${lib.concatStringsSep ", " resolvers6};
  '';

  local6Conf = fclib.configFromFile "/etc/nixos/localconfig-dhcpd6.conf" "";
in
{
  config = lib.mkIf role.enable {
    services.dhcpd4 = {
      enable = true;
      extraConfig = lib.concatStringsSep "\n\n" [
        baseConf
        dhcpd4Conf
        local4Conf
      ];
    };

    services.dhcpd6 = {
      enable = true;
      extraConfig = lib.concatStringsSep "\n\n" [
        baseConf
        dhcpd6Conf
        local6Conf
      ];
    };
  };
}
