{ config, pkgs, lib, ... }:

let
  role = config.flyingcircus.roles.mailserver;
  chpasswd = "/run/wrappers/bin/roundcube-chpasswd";

in lib.mkMerge [
  (lib.mkIf (role.enable && role.webmailHost != null) {
    services.postgresql.enable = true;

    security.wrappers = {
      roundcube-chpasswd = {
        source = "${pkgs.fc.roundcube-chpasswd}/bin/roundcube-chpasswd";
        owner = "vmail";
      };
    };

    services.roundcube = {
      enable = true;
      extraConfig = ''
        $config['archive_type'] = 'year';
        $config['managesieve_vacation'] = 1;
        $config['mime_types'] = '${pkgs.mime-types}/etc/mime.types';
        $config['password_chpasswd_cmd'] = '${chpasswd} ${role.passwdFile}';
        $config['password_confirm_current'] = true;
        $config['password_driver'] = 'chpasswd';
        $config['password_minimum_length'] = 10;
        $config['smtp_server'] = 'tls://${role.mailHost}';
        $config['smtp_user'] = '%u';
        $config['smtp_pass'] = '%p';

      '';
      database = {
        username = "roundcube";
        password = "roundcube";
      };
      hostName = role.webmailHost;
      plugins = [
        "archive"
        "attachment_reminder"
        "emoticons"
        "help"
        "managesieve"
        "password"
        "zipdownload"
      ];
    };
  })

  (lib.mkIf (role.webmailHost != null && role.webmailHost != role.mailHost) {
    services.nginx.virtualHosts.${role.mailHost}.globalRedirect =
      role.webmailHost;
  })
]
