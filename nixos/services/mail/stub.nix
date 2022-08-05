{ config, pkgs, lib, ... }:

with builtins;

let
  role = config.flyingcircus.roles.mailstub;
  fclib = config.fclib;

  interfaces =
    lib.attrByPath [ "parameters" "interfaces" ] {} config.flyingcircus.enc;

  mainCf =
    lib.optionals role.explicitSmtpBind [
      "smtp_bind_address=${role.smtpBind4}"
      "smtp_bind_address6=${role.smtpBind6}"
    ] ++ [ (fclib.configFromFile "/etc/local/postfix/main.cf" "") ];

  masterCf = [ (fclib.configFromFile "/etc/local/postfix/master.cf" "") ];

  recipientCanonical = toFile "generic.pcre" ''
    /.*@.*\.fcio\.net$/ ${role.rootAlias}
  '';

  checkMailq = "${pkgs.fc.check-postfix}/bin/check_mailq";

  readme = ''
    Mail server stub is a minimally pre-configured Postfix instance.

    Put local Postfix configuration into this directory.

    - Postfix configuration statements should go into `main.cf`
    - Postfix service definitions should go into `master.cf`

    If you need to send mails to the outside world, this role needs quite an
    amount of manual configuration. Consider switching to the more
    fully-featured 'mailserver' role. Services provided by this role are,
    however, sufficient to send cron mails to a central address or dispatch
    incoming mails to application servers.

    This role shares some configuration options which the 'mailserver' role:
    mailHost, rootAlias, smtpBind[46], explicitSmtpBind. Refer to
    https://doc.flyingcircus.io/roles/fc-22.05-production/mailserver.html for
    explanation.
  '';

in {
  options = {
    flyingcircus.services.postfix.enable = lib.mkEnableOption ''
      Bare bones Postfix with basic checks and custom configuration.
    '';
  };

  config = (lib.mkIf config.flyingcircus.services.postfix.enable {
    services.postfix = {
      enable = true;
      enableSubmission = true;
      hostname = role.mailHost;
      extraConfig = lib.concatStringsSep "\n" mainCf;
      extraMasterConf = lib.concatStringsSep "\n" masterCf;
      config.recipient_canonical_maps =
        lib.mkDefault "pcre:${recipientCanonical}";
      # Trust all networks on the SRV interface.
      networks = lib.mkDefault (
        map fclib.quoteIPv6Address
        (attrNames (lib.attrByPath [ "srv" "networks" ] {} interfaces)));
      destination = lib.mkDefault [
        "localhost"
        role.mailHost
        config.networking.hostName
        "${config.networking.hostName}.fcio.net"
        "${config.networking.hostName}.gocept.net"
      ];
      rootAlias = role.rootAlias;
    };

    environment.etc."local/postfix/README.txt".text = readme;
    environment.systemPackages = with pkgs; [ mailutils ];

    flyingcircus.services.sensu-client.checks = {
      postfix_mailq =
        let
          mailq = "${pkgs.postfix}/bin/mailq";
        in {
          command = "sudo ${checkMailq} -w 50 -c 500 --mailq ${mailq}";
          notification = "Too many undelivered mails in Postfix mail queue";
          interval = 300;
        };

      postfix_smtp_port = {
        command = "check_smtp -H localhost -p 25 -e Postfix -w 5 -c 10 -t 60";
        notification = "Postfix SMTP port (25) not reachable";
      };

      postfix_submission_port = {
        command = "check_smtp -H localhost -p 587 -e Postfix -w 5 -c 10 -t 60";
        notification = "Postfix submission port (587) not reachable";
      };
    };

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ checkMailq ];
        groups = [ "sensuclient" ];
      }
    ];

    systemd.tmpfiles.rules = [
      "d /etc/local/postfix 2775 root service"
    ];

  });
}
