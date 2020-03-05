# Customer specific role
{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.roles.webdata_blackbee;

  firewallTrustedSSH = [
    # VPN prod
    "172.22.49.50"
    "2a02:248:101:63::1189"
    "2a02:248:101:62::1180"
    "2a02:248:101:62::1190"
    "195.62.126.67"

    # VPN stag
    "172.22.49.52"
    "2a02:248:101:63::118b"
    "195.62.126.68"
    "2a02:248:101:62::1182"
    "2a02:248:101:62::118f"

    # Azure prod/stag
    "192.168.203.0/24"
    "192.168.204.0/24"
  ];

  additional_hosts =
    if pathExists /srv/s-blackbee/hosts
    then readFile /srv/s-blackbee/hosts
    else "";

  routes = [ "10.0.0.0/24" "10.10.10.0/24" "10.242.2.0/24" ];
  gwHost = "172.22.49.50";

in
{
  options = {

    flyingcircus.roles.webdata_blackbee.enable =
      lib.mkEnableOption "Enable the customer specific role.";

  };

  config = lib.mkIf cfg.enable {

    environment.etc.blackbee.source = "/srv/s-blackbee/etc";

    system.activationScripts.webdata_blackbee = ''
      test -L /home/pricing || ln -s /srv/s-blackbee/pricing /home/pricing
      test -L /bin/bash || ln -s /run/current-system/sw/bin/bash /bin/bash
    '';

    networking.extraHosts = additional_hosts;

    systemd.services."network-external-routing-ionos" = rec {
      description = "Custom routing rules for external networks";
      after = [ "network-routing-ethsrv.service" "firewall.service" ];
      requires = after;
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "sys-subsystem-net-devices-ethsrv.device" ];
      path = with pkgs; [ gawk iproute glibc iptables ];

      serviceConfig =
        {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "network-external-routing-start" ''
            #! ${pkgs.stdenv.shell} -e
            ${lib.concatMapStringsSep "\n"
              (route: "ip -4 route add ${route} via ${gwHost} dev ethsrv")
              routes}
          '';
          ExecStop = pkgs.writeScript "network-external-routing-stop" ''
            #! ${pkgs.stdenv.shell}
            ${lib.concatMapStringsSep "\n"
              (route: "ip -4 route del ${route} via ${gwHost} dev ethsrv")
              routes}
          '';
          RemainAfterExit = true;
        };
      };

    environment.systemPackages = with pkgs; [
      htop
      innotop
      mailx
      mc
      percona # client is required on almost all nodes
      sshpass
      sysbench
      wget
    ];

    environment.shellAliases = {
      gopricing = "cd /home/pricing && sudo -u s-blackbee bash --login";
      more = "less -e";
    };

    systemd.extraConfig = ''
      DefaultLimitNOFILE=64000
      DefaultLimitNPROC=64173
      DefaultLimitSIGPENDING=64173
    '';

    # Don't allow SSH access from everywhere. Set custom iptables rules.
    services.openssh.openFirewall = lib.mkForce false;
    networking.firewall.extraCommands = let
      allowed = lib.concatStringsSep "\n"
        (map
          (ip: ''
            ${fclib.iptables ip} -A nixos-fw -s ${ip} -p tcp --dport 22 \
              -j nixos-fw-accept
          '')
          (config.flyingcircus.static.firewall.trusted ++ firewallTrustedSSH));
    in

    ''
      # Allow ssh from trusted nets/hosts
      ${allowed}

      # Allow ionos routes
      ${lib.concatMapStringsSep "\n"
        (route: "iptables -A nixos-fw -s ${route} -j nixos-fw-accept")
        routes}
    '';

    # Policy routing doesn't work with the routing via VPN. But everything
    # works without policy routing. So disable it.
    flyingcircus.network.policyRouting.enable = lib.mkForce false;

  };
}
