{
  config,
  pkgs,
  lib,
  ...
}:

with builtins;

let
  role = config.flyingcircus.roles.router;
  inherit (config) fclib;
  inherit (config.flyingcircus) location;
  inherit (config.networking) hostName;
  suffix = "gocept.net";

  # TODO: add role option for twinned networks with dhcp
  dhcpNetworks = [ "ipmi" ] ++ role.routerGatewayNetworks;
  dhcpInterfaces = map (net: fclib.network."${net}".interface) role.routerGatewayNetworks;

  bootServer = head fclib.network.mgm.v4.defaultGateways;

  baseConfig = {
    dhcp-ddns = {
      enable-updates = false;
    };
    valid-lifetime = 1800;
    max-valid-lifetime = 7200;
  };

  kea4Config = {
    interfaces-config = {
      interfaces = dhcpInterfaces;
      dhcp-socket-type = "raw";
    };

    lease-database = {
      type = "memfile";
      persist = true;
      name = "/var/lib/kea/dhcp4.leases";
    };

    authoritative = true; # match previous isc-dhcpd behaviour

    option-data = [
      {
        name = "domain-name";
        data = suffix;
      }
      {
        name = "domain-search";
        data = "${suffix}, ${location}.${suffix}";
      }
      {
        name = "domain-name-servers";
        data = lib.concatStringsSep ", " role.dhcpResolversV4;
      }
      # NTP options set on a per-subnet basis by fc-kea
    ];

    next-server = bootServer;

    # default to efi netboot. bios clients and the ipxe loader are
    # identified with client classes, with the options specified in
    # the first match taking precedence.
    boot-file-name = "ipxe.efi";
    client-classes = [
      {
        name = "iPXE";
        test = "option[user-class].exists and (option[user-class].hex == 'iPXE')";
        boot-file-name = "flyingcircus.ipxe";
      }
      {
        name = "BIOS PXE";
        test = "substring(option[vendor-class-identifier].hex, 15, 5) == '00000'";
        boot-file-name = "undionly.kpxe";
      }
    ];
  };

  kea6Config = {
    interfaces-config = {
      interfaces = dhcpInterfaces;
    };

    lease-database = {
      type = "memfile";
      persist = true;
      name = "/var/lib/kea/dhcp6.leases";
    };

    option-data = [
      {
        name = "dns-servers";
        data = lib.concatStringsSep ", " role.dhcpResolversV6;
      }
      {
        name = "domain-search";
        data = "${suffix}, ${location}.${suffix}";
      }
      # no direct equivalent to dhcpv4 option 15 in dhcpv6, fqdn
      # configured on a per-host basis.
    ];
  };

  configUpdateScript = pkgs.writeShellScript "update-kea-config" ''
    # Generate DHCP server configuration
    ${pkgs.fc.agent}/bin/fc-kea -4 -L ${location} -o /etc/nixos/localconfig-dhcpd4.json -e ipmi ${
      lib.concatMapStringsSep " " (net: "-n ${net}") dhcpNetworks
    }
    ${pkgs.fc.agent}/bin/fc-kea -6 -L ${location} -o /etc/nixos/localconfig-dhcpd6.json -e ipmi ${
      lib.concatMapStringsSep " " (net: "-n ${net}") dhcpNetworks
    } -d ${suffix}
  '';

in
{
  options = with lib; {
    flyingcircus.services.dhcpd4.localconfig = mkOption {
      type = types.attrs;
      default = fclib.jsonFromFile "/etc/nixos/localconfig-dhcpd4.json" "{}";
    };
    flyingcircus.services.dhcpd6.localconfig = mkOption {
      type = types.attrs;
      default = fclib.jsonFromFile "/etc/nixos/localconfig-dhcpd6.json" "{}";
    };
  };

  config = lib.mkIf role.enable {
    flyingcircus.agent.extraPreCommands = ''
      ${configUpdateScript}
    '';

    services.kea.dhcp4 = {
      enable = role.isPrimary;
      settings = (baseConfig // kea4Config // config.flyingcircus.services.dhcpd4.localconfig);
    };
    services.kea.dhcp6 = {
      enable = role.isPrimary;
      settings = (baseConfig // kea6Config // config.flyingcircus.services.dhcpd6.localconfig);
    };

    services.atftpd = {
      enable = role.isPrimary;
      extraOptions = [
        "--verbose=5"
      ];
      root = pkgs.runCommand "tftpd-root-for-dhcpd4" { } ''
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
