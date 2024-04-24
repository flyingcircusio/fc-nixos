{ config, lib, pkgs, ... }:

with builtins;

let
  inherit (config.flyingcircus) location;
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  kickInterfaces = fclib.writeShellApplication {
    name = "kick-interfaces";
    runtimeInputs = with pkgs; [ ethtool ];
    text = lib.readFile ./kick-interfaces.sh;
  };

  martianNetworks =
    lib.filter
      (n: n != "")
      (lib.splitString "\n" (lib.readFile ./martian_networks));

  martianIptablesInput =
    (lib.concatMapStringsSep "\n"
      (network:
        "${fclib.iptables network} -A nixos-fw -i ethtr+ " +
        "-s ${network} -j DROP")
      martianNetworks);

  martianIptablesForward =
    (lib.concatMapStringsSep "\n"
      (network:
        "${fclib.iptables network} -A fc-router-forward -i ethtr+ " +
        "-s ${network} -j DROP")
      # Also drop link-local addresses here.
      (martianNetworks ++ [ "fe80::/10" ]));
in
{
  options = {
    flyingcircus.roles.router = with lib; {
      enable = mkEnableOption "Router";
      supportsContainers = fclib.mkDisableContainerSupport;
      isPrimary = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  imports = [
    ./bind
    ./bird2
    ./keepalived
    ./chrony.nix
    ./dhcpd.nix
    ./radvd.nix
  ];

  config = lib.mkIf role.enable {

    flyingcircus.networking.enableInterfaceDefaultRoutes = false;

    boot.kernel.sysctl = {
      # It's a router: we want forwarding, obviously
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv4.conf.default.forwarding" = 1;
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;

      # Avoid neighbour discovery table overflow on our relatively large segments
      "net.ipv4.neigh.default.gc_thresh1" = lib.mkOverride 90 4096;
      "net.ipv4.neigh.default.gc_thresh2" = lib.mkOverride 90 16384;
      "net.ipv4.neigh.default.gc_thresh3" = lib.mkOverride 90 32768;
      "net.ipv6.neigh.default.gc_thresh1" = lib.mkOverride 90 4096;
      "net.ipv6.neigh.default.gc_thresh2" = lib.mkOverride 90 16384;
      "net.ipv6.neigh.default.gc_thresh3" = lib.mkOverride 90 32768;

      # fair queuing + codel to avoid buffer bloat in WAN
      "net.core.default_qdisc" = "fq_codel";

      # Ensure proper conntracking configuration: if we run out of entries then
      # packets will get dropped.
      #
      # TODO wrong URL
      # See https://stats.flyingcircus.io/grafana/dashboard/db/kenny01-conntrack
      # for current usage statistics
      #
      # This should use about 300-500 MiB with ~32 entries in each bucket
      # https://johnleach.co.uk/words/372/netfilter-conntrack-memory-usage
      "net.netfilter.nf_conntrack_max" = lib.mkOverride 90 1048576;
      "net.netfilter.nf_conntrack_buckets" = 32768;
    };

    environment.etc."specialisation".text = lib.mkDefault "";

    environment.systemPackages = with pkgs; [
      kickInterfaces
      pmacct
    ];

    environment.shellAliases = {
    };

    networking.firewall.extraCommands =
      (lib.concatStringsSep "\n" [
        martianIptablesInput
        ''
        ip46tables -N fc-router-forward 2>/dev/null || true
        ip46tables -A FORWARD -j fc-router-forward
        ''
        martianIptablesForward
        ''
        # TFTP
        ip46tables -A nixos-fw -p tcp --dport 69 -j nixos-fw-accept
        ip46tables -A nixos-fw -p udp --dport 69 -j nixos-fw-accept
        # Video for WHQ
        ip46tables -A nixos-fw -i ethvideo -j nixos-fw-accept
      '']);

    networking.firewall.extraStopCommands = ''
      ip46tables -D FORWARD -j fc-router-forward
      ip46tables -F fc-router-forward 2>/dev/null || true
      ip46tables -X fc-router-forward 2>/dev/null || true
    '';

    services.logrotate.extraConfig = ''
    '';

    specialisation.primary = {
      configuration = {
        system.nixos.tags = [ "primary" ];
        flyingcircus.roles.router.isPrimary = true;
        environment.etc."is_primary".text = "";
        environment.etc."specialisation".text = "primary";
      };
    };

    flyingcircus.services.sensu-client = {
      checks = {
      };

      expectedConnections = {
        warning = 18000;
        critical = 25000;
      };
    };

    flyingcircus.agent = {
      extraPreCommands = ''
        fc-dhcpd -4 -o /etc/nixos/localconfig-dhcpd4.conf ${location}
        fc-dhcpd -6 -o /etc/nixos/localconfig-dhcpd6.conf ${location}
        # Updates files in /etc/bind and /etc/bind/pri where also Nix-generated config exists.
        fc-zones
      '';
    };

  };
}
