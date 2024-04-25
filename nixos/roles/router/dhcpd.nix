{ config, pkgs, lib, ...}:

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
    authoritative;
    log-facility local1;
    default-lease-time 1800;
    max-lease-time 7200;
    option domain-name "${suffix}";
    option domain-search "${suffix}", "${location}.${suffix}";
    option ntp-servers ${hostName};
  '';

  resolvers4 = if (hasAttr location config.flyingcircus.static.nameservers)
        then config.flyingcircus.static.nameservers.${location}
        else [];

  resolvers6 =
        if (hasAttr location config.flyingcircus.static.nameservers6)
        then config.flyingcircus.static.nameservers6.${location}
        else [];

  dhcpd4Conf = ''
    # DHCPv4 specific general options
    option domain-name-servers ${lib.concatStringsSep ", " resolvers4};

    if exists user-class and option user-class = "iPXE" {
        # We are currently running iPXE: load the static boot script.
        filename "flyingcircus.ipxe";
    } else {
        # We are currently running the built-in ROM PXE and switch to boot the
        # iPXE kernel.
        filename "undionly.kpxe"; # we are in burned in PXE and load iPXE kernel
    }
    next-server ${location}-router.mgm.${location}.${suffix};
    '';

  dhcpd6Conf = ''
    # DHCPv6 specific general options
    option dhcp6.name-servers ${lib.concatStringsSep ", " resolvers6};
  '';
in
{
  options = with lib; {
    flyingcircus.services.dhcpd4.localconfig = mkOption {
      type = types.str;
      default = fclib.configFromFile "/etc/nixos/localconfig-dhcpd4.conf" "";
    };
    flyingcircus.services.dhcpd6.localconfig = mkOption {
      type = types.str;
      default = fclib.configFromFile "/etc/nixos/localconfig-dhcpd6.conf" "";
    };
  };

  config = lib.mkIf (role.enable && role.isPrimary) {
    services.dhcpd4 = {
      enable = true;
      interfaces = [
        fclib.network.fe.interface
        fclib.network.srv.interface
        fclib.network.mgm.interface
      ];
      configFile = pkgs.writeText "dhcpd4.conf" ''
        ${baseConf}
        ${dhcpd4Conf}
        ${config.flyingcircus.services.dhcpd4.localconfig}
      '';
    };

    services.dhcpd6 = {
      enable = true;
      interfaces = [
        fclib.network.fe.interface
        fclib.network.srv.interface
        fclib.network.mgm.interface
      ];
      configFile = pkgs.writeText "dhcpd6.conf" ''
        ${baseConf}
        ${dhcpd6Conf}
        ${config.flyingcircus.services.dhcpd6.localconfig}
      '';
    };

    services.tftpd = {
      enable = true;
      path = ... {
         # place a file called "flyingcircus.ipxe" in this path, take it from ./flyingcircus.ipxe
         # place a file called "undionly.kpxe" in this path, take it from ${pkgs.ipxe}/undionly.kpxe
      };
    };

    networking.firewall.extraCommands = ''
      # TFTP
      ip46tables -A nixos-fw -i ${fclib.network.mgm.interface} -p udp --dport 69 -j nixos-fw-accept
    '';

  };
}
