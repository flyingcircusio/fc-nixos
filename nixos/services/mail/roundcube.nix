{ config, pkgs, lib, ... }:

let
  role = config.flyingcircus.roles.mailserver;
  chpasswdPkg = pkgs.fc.roundcube-chpasswd-py;
  fclib = config.fclib;

in lib.mkMerge [
  (lib.mkIf (role.enable && role.webmailHost != null) {

    assertions = [ {
      assertion = config.flyingcircus.services.postgresql.majorVersion != "not set";
      message = ''
        PostgreSQL version must be set explicitly!
        Must be defined either by using a postgresql role or by setting it via custom config like:

        flyingcircus.services.postgresql.majorVersion = "13";
      '';
    }];

    flyingcircus.services.postgresql = {
      enable = true;
      majorVersion = fclib.mkPlatform "not set";
      autoUpgrade = {
        enable = true;
        expectedDatabases = [ "roundcube" ];
      };
    };

    flyingcircus.passwordlessSudoPackages = [{
      commands = [ "bin/roundcube-chpasswd" ];
      package = chpasswdPkg;
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
        $config['mime_types'] = '${pkgs.mailcap}/etc/mime.types';
        $config['password_chpasswd_cmd'] = '/run/wrappers/bin/sudo -u vmail ${chpasswdPkg}/bin/roundcube-chpasswd --passwd-file ${role.passwdFile}';
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
