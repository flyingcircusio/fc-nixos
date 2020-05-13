{ config, lib, pkgs, ... }:

with builtins;

# Explanation of various host names:
# - fqdn: "raw" machine name. Points to the srv address which is usually not
#   reachable from the outside but occasionally used for locally generated mail
#   (e.g., cron)
# - mailHost: HELO name
# - domains: list of mail domains for which regular mail accounts exist

let
  snm = fetchTarball {
    url = "https://github.com/flyingcircusio/nixos-mailserver/archive/d1bc7eb2b532bc0f65f52cfd4b99368a0e2bb3dc.tar.gz";
    sha256 = "1j6bfafng0309mp7r2bd02nlhfy1zyl6r8cbs03yrwz70y20q4ka";
  };

  role = config.flyingcircus.roles.mailserver;
  svc = config.flyingcircus.services.mail;
  fclib = config.fclib;
  fqdn = with config.networking; "${hostName}.${domain}";
  primaryDomain = if role.domains != [] then elemAt role.domains 0 else fqdn;
  vmailDir = "/srv/mail";
  fallbackGenericVirtual = ''
    postmaster@${primaryDomain} root@${role.mailHost}
    abuse@${primaryDomain} root@${role.mailHost}
  '';
  userAliases =
    concatStringsSep "\n" (
      (map (e: "${e.uid}: ${concatStringsSep ", " e.email_addresses}"))
      config.flyingcircus.users.userData);

in {
  imports = [
    # XXX conditional import?
    snm
    ./rspamd.nix
    ./roundcube.nix
  ];

  options = {
    flyingcircus.services.mail.enable = lib.mkEnableOption ''
      Mail server (SNM) with Postfix, Dovecot, rspamd, DKIM & SPF
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf svc.enable {
      environment.etc."local/mail/README.txt".source = ./README;
    })

    (lib.mkIf (svc.enable && role.domains != []) {

      environment = {
        etc = {
          # refer to the source for a comprehensive list of options:
          # https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/default.nix
          # generate password with `mkpasswd -m sha-256 PASSWD` and put it either
          # here (read-only) or into passwdFile (user-changeable)
          "local/mail/users.json.example".text = (toJSON {
            "user@${primaryDomain}" = {
              hashedPassword = "";
              aliases = [ "user1@${primaryDomain}" ];
              quota = "4G";
              sieveScript = null;
              catchAll = [ "subdomain.${primaryDomain}" ] ++ (
                tail role.domains);
            };
          });

          "local/mail/dns.zone".text =
            import ./zone.nix { inherit config lib; };

          # these must use one of the configured domains as targets
          "local/mail/local_valiases.json.example".text = (toJSON {
            "postmaster@${primaryDomain}" = "user@${primaryDomain}";
            "abuse@${primaryDomain}" = "user@${primaryDomain}";
          });
        };

        systemPackages = with pkgs; [
          mkpasswd
        ];
      };

      flyingcircus.services.sensu-client.checks =
      let plug = "${pkgs.monitoring-plugins}/libexec";
      in {
        postfix_smtp = {
          notification = "Postfix listening on SMTP port 25";
          command = "${plug}/check_smtp -H ${role.mailHost} -S -F ${fqdn} " +
            "-w 5 -c 30";
        };
        postfix_submission = {
          notification = "Postfix listening on submission port 587";
          command = "${plug}/check_smtp -H ${role.mailHost} -p 587 -S " +
            "-F ${fqdn} -w 5 -c 30";
        };
        dovecot_imap = {
          notification = "Dovecot listening on IMAP port 143";
          command = "${plug}/check_imap -H ${role.mailHost} -w 5 -c 30";
        };
        dovecot_imaps = {
          notification = "Dovecot listening on IMAPs port 993";
          command = "${plug}/check_imap -H ${role.mailHost} -p 993 -S -w 5 -c 30";
        };
      };

      # SNM specific configuration, see
      # https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/default.nix
      mailserver = {
        enable = true;
        inherit (role) domains;
        fqdn = role.mailHost;
        loginAccounts = fclib.jsonFromFile "/etc/local/mail/users.json" "{}";
        extraVirtualAliases =
          fclib.jsonFromFile "/etc/local/mail/local_valiases.json" "{}";
        certificateScheme = 3;
        enableImapSsl = true;
        enableManageSieve = true;
        mailDirectory = vmailDir;
        mailboxes = [
          { name = "Trash"; auto = "create"; specialUse = "Trash"; }
          { name = "Junk"; auto = "subscribe"; specialUse = "Junk"; }
          { name = "Drafts"; auto = "subscribe"; specialUse = "Drafts"; }
          { name = "Sent"; auto = "subscribe"; specialUse = "Sent"; }
          { name = "Archives"; auto = "subscribe"; specialUse = "Archive"; }
        ];
        policydSPFExtraConfig = ''
          skip_addresses = 127.0.0.0/8,::ffff:127.0.0.0/104,::/64,${
            concatStringsSep "," (fclib.listenAddresses "ethfe")}
          HELO_Whitelist = ${fqdn},${role.mailHost}
        '';
        vmailGroupName = "vmail";
        vmailUserName = "vmail";
      };

      services.dovecot2.extraConfig = ''
        passdb {
          driver = passwd-file
          args = ${role.passwdFile}
        }

        plugin {
          mail_plugins = $mail_plugins expire
          expire = Trash
          expire2 = Trash/*
          expire3 = Junk
          expire_cache = yes
        }
      '';

      services.nginx.virtualHosts =
        let
          cfgForDomain = domain:
          lib.nameValuePair "autoconfig.${domain}" {
            addSSL = true;
            enableACME = true;
            locations."/mail/config-v1.1.xml".alias = (import ./autoconfig.nix {
              inherit domain pkgs lib;
              inherit (role) mailHost webmailHost;
            });
          };
        in listToAttrs (map cfgForDomain role.domains);

      services.postfix = {
        destination = [
          role.mailHost
          config.networking.hostName
          fqdn
          "localhost"
        ];
        extraConfig = ''
          empty_address_recipient = postmaster
          enable_long_queue_ids = yes
          local_header_rewrite_clients =
            permit_mynetworks,
            permit_sasl_authenticated
          recipient_canonical_maps = tcp:localhost:10002
          recipient_canonical_classes = envelope_recipient, header_recipient
          sender_canonical_maps = tcp:localhost:10001
          sender_canonical_classes = envelope_sender
          smtp_bind_address = ${role.smtpBind4}
          smtp_bind_address6 = ${role.smtpBind6}
          smtpd_client_restrictions =
            permit_mynetworks,
            reject_rbl_client ix.dnsbl.manitu.net,
            reject_unknown_client_hostname
          smtpd_data_restrictions = reject_unauth_pipelining
          smtpd_helo_restrictions =
            permit_sasl_authenticated,
            reject_unknown_helo_hostname

          # included from /etc/local/mail/main.cf
          ${fclib.configFromFile "/etc/local/mail/main.cf" ""}
        '';
        extraAliases = ''
          abuse: root
          devnull: /dev/null
          mail: root
        '' + userAliases;
        inherit (role) rootAlias;
        virtual =
          fclib.configFromFile
          "/etc/local/mail/remote_valiases.map" fallbackGenericVirtual;
      };

      services.postsrsd = {
        enable = true;
        domain = primaryDomain;
        excludeDomains =
          if role.domains != []
          then tail config.mailserver.domains ++ [ role.mailHost fqdn ]
          else [];
      };

      systemd.services.dovecot2-expunge = {
        script = ''
          doveadm expunge -A mailbox Trash savedbefore 7d || true
          doveadm expunge -A mailbox Junk savedbefore 30d || true
        '';
        path = with pkgs; [ dovecot ];
        startAt = "04:39:47";
      };

      systemd.tmpfiles.rules = [
        "f ${role.passwdFile} 0660 vmail service"
        "d /etc/local/mail 02775 postfix service"
        "f /etc/local/mail/local_valiases.json 0664 postfix service - {}"
        "f /etc/local/mail/remote_valiases.map 0664 postfix service"
        "f /etc/local/mail/users.json 0664 postfix service - {}"
        "f /etc/local/mail/main.cf 0664 postfix service"
      ];

    })

    (lib.mkIf (svc.enable && config.services.telegraf.enable &&
               role.domains != []) {
      flyingcircus.services.telegraf.inputs.postfix = [{
        queue_directory = "/var/lib/postfix/queue";
      }];

      systemd.services.postfix.postStart =
        let
          setfacl = "${pkgs.acl}/bin/setfacl";
        in ''
          ${setfacl} -m u:telegraf:rX,m:rX \
            /var/lib/postfix/queue/{active,hold,incoming,deferred,maildrop}
          ${setfacl} -dm u:telegraf:rX,m:rX \
            /var/lib/postfix/queue/{active,hold,incoming,deferred,maildrop}
        '';
    })
  ];
}
