{ config, pkgs, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.mailserver;
  fclib = config.fclib;

  interfaces =
    lib.attrByPath [ "parameters" "interfaces" ] {} config.flyingcircus.enc;

  listen4 = filter fclib.isIp4 cfg.smtpBindAddresses;
  listen6 = filter fclib.isIp6 cfg.smtpBindAddresses;

  mainCf = [
    (lib.optionalString
      (length listen4 > 0)
      "smtp_bind_address=${head listen4}")
    (lib.optionalString
      (length listen6 > 0)
      "smtp_bind_address6=${head listen6}")
    (fclib.configFromFile "/etc/local/postfix/main.cf" "")
    (lib.optionalString
      (lib.pathExists "/etc/local/postfix/canonical.pcre")
      "canonical_maps = pcre:${/etc/local/postfix/canonical.pcre}\n")
  ];

  masterCf = [
    (lib.optionalString
      (lib.pathExists "/etc/local/postfix/master.cf")
      (lib.readFile /etc/local/postfix/master.cf))
  ];

  checkMailq = pkgs.fc.sensu-plugins-postfix + /bin/check-mailq.rb;
in
{
  options = {
    flyingcircus.services.postfix.enable = lib.mkEnableOption ''
      Postfix mailserver|mailout role with FCIO custom config
    '';
  };

  config = (lib.mkIf config.flyingcircus.services.postfix.enable {
    services.postfix = {
      enable = true;
      enableSubmission = true;
      hostname = cfg.hostname;
      extraConfig = lib.concatStringsSep "\n" mainCf;
      extraMasterConf = lib.concatStringsSep "\n" masterCf;
      # Trust all networks on the SRV interface.
      networks =
        map fclib.quoteIPv6Address
        (attrNames (lib.attrByPath [ "srv" "networks" ] {} interfaces));
      destination = [
        "localhost"
        cfg.hostname
        config.networking.hostName
        "${config.networking.hostName}.gocept.net"
        "${config.networking.hostName}.fcio.net"
      ];
    };

    environment.etc."local/postfix/README.txt".text = ''
      Put your local postfix configuration here.

      Use `main.cf` for pure configuration settings like
      setting message_size_limit. Please do use normal main.cf syntax,
      as this will extend the basic configuration file.

      Make usage of `myhostname` to provide a hostname Postfix shall
      use to configure its own myhostname variable. If not set, the
      default hostname will be used instead.

      If you need to reference to some map, these are currently available:
      * canonical_maps - /etc/local/postfix/canonical.pcre

      The file `master.cf` may contain everything you want to add to
      postfix' master.cf-file e.g. to enable the submission port.

      In case you need to extend this list, get in contact with our
      support.
    '';

    environment.systemPackages = with pkgs; [ mailutils ];

    flyingcircus.services.sensu-client.checks = {
      postfix_mailq = {
        command = ''
          sudo ${checkMailq} -w 200 -c 400
        '';
        notification = "Too many undelivered mails in Postfix mail queue.";
      };

      postfix_smtp_port = {
        command = ''
          check_smtp -H localhost -p 25 -e Postfix -w 5 -c 10 -t 60
        '';
        notification = "Postfix SMTP (25) not reachable at localhost.";
      };

      postfix_submission_port = {
        command = ''
          check_smtp -H localhost -p 587 -e Postfix -w 5 -c 10 -t 60
        '';
        notification = "Postfix Submission (587) not reachable at localhost.";
      };
    };

    security.sudo.extraRules = [
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
