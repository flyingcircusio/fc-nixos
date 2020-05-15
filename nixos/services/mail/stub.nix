{ config, pkgs, lib, ... }:

with builtins;

let
  role = config.flyingcircus.roles.mailstub;
  fclib = config.fclib;

  interfaces =
    lib.attrByPath [ "parameters" "interfaces" ] {} config.flyingcircus.enc;

  mainCf = [
    "smtp_bind_address=${role.smtpBind4}"
    "smtp_bind_address6=${role.smtpBind6}"
    (fclib.configFromFile "/etc/local/postfix/main.cf" "")
  ];

  masterCf = [
    (fclib.configFromFile "/etc/local/postfix/master.cf" "")
  ];

  checkMailq = "${pkgs.fc.check-postfix}/bin/check_mailq";

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
      # Trust all networks on the SRV interface.
      networks =
        map fclib.quoteIPv6Address
        (attrNames (lib.attrByPath [ "srv" "networks" ] {} interfaces));
      destination = [
        "localhost"
        role.mailHost
        config.networking.hostName
        "${config.networking.hostName}.fcio.net"
      ];
      rootAlias = role.rootAlias;
    };

    environment.etc."local/postfix/README.txt".text = ''
      Put local Postfix configuration into this directory.

      * Postfix configuration statements should go into `main.cf`

      * Postfix service definitions should go into `master.cf`
    '';

    environment.systemPackages = with pkgs; [ mailutils ];

    flyingcircus.services.sensu-client.checks = {
      postfix_mailq =
        let
          mailq = "${pkgs.postfix}/bin/mailq";
        in {
          command = "sudo ${checkMailq} -w 50 -c 500 --mailq ${mailq}";
          notification = "Too many undelivered mails in Postfix mail queue";
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
