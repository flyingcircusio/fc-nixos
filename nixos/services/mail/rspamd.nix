{ config, pkgs, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus;
  role = cfg.roles.mailserver;
  interfaces = lib.attrByPath [ "parameters" "interfaces" ] {} cfg.enc;
  localNets =
    [ "127.0.0.0/8" "::/64" ] ++
    (lib.flatten (
      lib.mapAttrsToList (_: iface: lib.attrNames iface.networks) interfaces));

  # see also genericVirtual in default.nix
  spamtrapMap = builtins.toFile "spamtrap.map" ''
    /^spam@${role.mailHost}$/
  '';

in
{
  imports = [
    ../redis.nix
  ];

  config = {
    services.nginx = lib.mkIf (role.webmailHost != null) {
      upstreams."@rspamd".servers = {
        "unix:/run/rspamd/worker-controller.sock" = {};
      };

      virtualHosts.${role.webmailHost}.locations."/rspamd/" = {
        proxyPass = "http://@rspamd/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };

    services.rspamd.locals = {
      "options.inc".text = ''
        local_addrs = [${
          concatStringsSep ", " (map (n: "\"${n}\"") localNets)}]
      '';

      "greylist.conf".text = ''
        expire = 7d;
        ipv4_mask = 24;
        ipv6_mask = 56;
      '';

      "mx_check.conf".text = ''
        enabled = true;
      '';

      "replies.conf".text = ''
        action = "no action";
        expire = 3d;
      '';

      "spamtrap.conf".text = ''
        action = "reject";
        enabled = true;
        learn_spam = true;
        map = file://${spamtrapMap};
      '';

      "url_reputation.conf".text = ''
        enabled = true;
      '';

      # controller web UI not reachable from the outside
      "worker-controller.inc".text = ''
        password = "";
        enable_password = "";
        dynamic_conf = "/var/lib/rspamd/rspamd_dynamic";
        static_dir = "${pkgs.rspamd}/share/rspamd/www";
      '';
    };
  };
}
