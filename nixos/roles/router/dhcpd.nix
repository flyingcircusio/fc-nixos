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
      # https://wiki.fogproject.org/wiki/index.php?title=BIOS_and_UEFI_Co-Existence
      # and https://ipxe.org/cfg/platform
      if substring (option vendor-class-identifier, 15, 5) = "00000" {
          # BIOS client
          filename "undionly.kpxe";
      }
      else {
          # default to EFI 64 bit. This should work for classes 7 and 9 as long
          # as secure boot is disabled.
          filename "ipxe.efi";
      }
    }
    next-server ${location}-router.mgm.${location}.${suffix};
    '';

  dhcpd6Conf = ''
    # DHCPv6 specific general options
    option dhcp6.name-servers ${lib.concatStringsSep ", " resolvers6};
  '';

  dhcpInterfaces = let
    names = [ "mgm" "srv" "fe" ] ++
            (config.flyingcircus.static.additionalDhcpNetworks."${location}" or []);
  in
    map (net: fclib.network."${net}".interface) names;
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

  config = lib.mkIf (role.enable) {
    services.dhcpd4 = {
      enable = role.isPrimary;
      interfaces = dhcpInterfaces;
      configFile = pkgs.writeText "dhcpd4.conf" ''
        ${baseConf}
        ${dhcpd4Conf}
        ${config.flyingcircus.services.dhcpd4.localconfig}
      '';
    };

    services.dhcpd6 = {
      enable = role.isPrimary;
      interfaces = dhcpInterfaces;
      configFile = pkgs.writeText "dhcpd6.conf" ''
        ${baseConf}
        ${dhcpd6Conf}
        ${config.flyingcircus.services.dhcpd6.localconfig}
      '';
    };

    services.atftpd = {
      enable = role.isPrimary;
      extraOptions = [
        "--verbose=5"
      ];
      root = pkgs.runCommand "tftpd-root-for-dhcpd4" {} ''
        mkdir $out
        # place a file called "flyingcircus.ipxe" in this path, take it from ./flyingcircus.ipxe
        cp ${./flyingcircus.ipxe} $out/flyingcircus.ipxe
        # place a file called "undionly.kpxe" in this path, take it from ${pkgs.ipxe}/undionly.kpxe
        cp ${pkgs.ipxe}/undionly.kpxe $out/
        cp ${pkgs.ipxe}/ipxe.efi $out/
      '';
    };

    networking.firewall.extraCommands = ''
      # TFTP
      ip46tables -A nixos-fw -i ${fclib.network.mgm.interface} -p udp --dport 69 -j nixos-fw-accept
    '';

  };
}
