{ config, pkgs, lib, ... }:

let
  role = config.flyingcircus.roles.mailserver;
  chpasswd = "${pkgs.fc.roundcube-chpasswd}/bin/roundcube-chpasswd";
  fclib = config.fclib;

in lib.mkMerge [
  (lib.mkIf (role.enable && role.webmailHost != null) {
    services.postgresql.enable = true;

    flyingcircus.passwordlessSudoRules = [{
      commands = [ chpasswd ];
      users = [ "roundcube" ];
      runAs = "vmail";
    }];

    services.nginx.virtualHosts.${role.webmailHost} = {
      forceSSL = true;
      enableACME = true;
      listenAddresses = fclib.network.fe.dualstack.addressesQuoted;
    };

    services.roundcube = {
      enable = true;
      extraConfig = ''
        $config['archive_type'] = 'year';
        $config['managesieve_vacation'] = 1;
        $config['mime_types'] = '${pkgs.mime-types}/etc/mime.types';
        $config['password_chpasswd_cmd'] = '/run/wrappers/bin/sudo -u vmail ${chpasswd} ${role.passwdFile}';
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
]
