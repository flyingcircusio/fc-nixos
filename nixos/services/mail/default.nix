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
    url = "https://github.com/flyingcircusio/nixos-mailserver/archive/e4f8e0c154f3f60487fd9ca8c39f90771c700195.tar.gz";
    sha256 = "0q535b14h7jln09v1q833ixily6c7vbksbg4bl9pzn86k11fcxff";
  };

  role = config.flyingcircus.roles.mailserver;
  svc = config.flyingcircus.services.mail;
  fclib = config.fclib;
  primaryDomain =
    if role.domains != [] then elemAt role.domains 0 else "example.org";
  vmailDir = "/srv/mail";
  fallbackGenericVirtual = ''
    postmaster@${primaryDomain} root@${role.mailHost}
    abuse@${primaryDomain} root@${role.mailHost}
  '';
  userAliases =
    concatStringsSep "\n" (
      (map (e: "${e.uid}: ${concatStringsSep ", " e.email_addresses}"))
      config.flyingcircus.users.userData);
  checkMailq = "${pkgs.fc.check-postfix}/bin/check_mailq";

in {
  imports = [
    snm
    ./roundcube.nix
    ./rspamd.nix
    ./stub.nix
  ];

  options = {
    flyingcircus.services.mail.enable = lib.mkEnableOption ''
      Mail server (SNM) with Postfix, Dovecot, rspamd, DKIM & SPF
    '';
  };

  config =
  let
    dynamicMapFiles = lib.flatten (lib.attrValues role.dynamicMaps);
    dynamicMapHash = p: "${baseNameOf p}-${substring 0 8 (hashString "sha1" p)}";
  in lib.mkMerge [
    (lib.mkIf svc.enable {
      environment.etc."local/mail/README.txt".source = ./README;
    })

    (lib.mkIf svc.enable {
      environment.etc = {
        "local/mail/config.json.example".text = (toJSON {
          domains = [ primaryDomain "subdomain.${primaryDomain}" ];
          mailHost = "mail.${primaryDomain}";
          webmailHost = "webmail.${primaryDomain}";
          dynamicMaps = { transport = [ "/etc/local/mail/transport" ]; };
        });

        # refer to the source for a comprehensive list of options:
        # https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/default.nix
        # generate password with `mkpasswd -m sha-256 PASSWD` and put it either
        # here (read-only) or into passwdFile (user-changeable)
        "local/mail/users.json.example".text = (toJSON {
          "user@${primaryDomain}" = {
            hashedPassword = "(use 'mkpasswd -m sha-256 PASSWORD')";
            aliases = [ "user1@${primaryDomain}" ];
            quota = "4G";
            sieveScript = null;
            catchAll = [ "subdomain.${primaryDomain}" ];
          };
        });
      };
    })

    (lib.mkIf (svc.enable && role.domains != []) (
    let
      fqdn = with config.networking; "${hostName}.${domain}";
    in {
      environment = {
        etc = {
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
      let
        plug = "${pkgs.monitoring-plugins}/libexec";
        mailq = "${pkgs.postfix}/bin/mailq";
      in {
        postfix_mailq = {
          command = "sudo ${checkMailq} -w 200 -c 2000 --mailq ${mailq}";
          notification = "Too many undelivered mails in Postfix mail queue";
        };
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

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [ checkMailq ];
          groups = [ "sensuclient" ];
        }
      ];

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

        config = {
          empty_address_recipient = "postmaster";
          enable_long_queue_ids = true;
          local_header_rewrite_clients = [
            "permit_mynetworks"
            "permit_sasl_authenticated"
          ];
          recipient_canonical_maps = "tcp:localhost:10002";
          recipient_canonical_classes = [
            "envelope_recipient"
            "header_recipient"
          ];
          sender_canonical_maps = "tcp:localhost:10001";
          sender_canonical_classes = "envelope_sender";
          smtpd_client_restrictions = [
            "permit_mynetworks"
            "reject_rbl_client ix.dnsbl.manitu.net"
            "reject_unknown_client_hostname"
          ];
          smtpd_data_restrictions = "reject_unauth_pipelining";
          smtpd_helo_restrictions = [
            "permit_sasl_authenticated"
            "reject_unknown_helo_hostname"
          ];
        } //
        (lib.optionalAttrs role.explicitSmtpBind {
          smtp_bind_address = role.smtpBind4;
          smtp_bind_address6 = role.smtpBind6;
        }) //
        (lib.mapAttrs (_mainCfParam: paths:
          (map (p: "hash:/var/lib/postfix/conf/${dynamicMapHash p}") paths))
          role.dynamicMaps);

        mapFiles = listToAttrs (map (path: {
          name = dynamicMapHash path;
          value = path;
        }) dynamicMapFiles);

        extraConfig = ''
          # included from /etc/local/mail/main.cf
          ${fclib.configFromFile "/etc/local/mail/main.cf" ""}
        '';

        extraAliases = ''
          abuse: root
          devnull: /dev/null
          mail: root
        '' + userAliases;

        inherit (role) rootAlias;
        virtual = lib.mkDefault fallbackGenericVirtual;
      };

      services.postsrsd = {
        enable = true;
        domain = primaryDomain;
        excludeDomains =
          if role.domains != []
          then tail config.mailserver.domains ++ [ role.mailHost fqdn ]
          else [];
      };

      system.activationScripts.postfix-dynamicMaps-permissions =
        lib.stringAfter [] (
          lib.concatStrings (map (file: ''
            if [[ ! -e "${file}" ]]; then
              # create file with the containing directory's group
              dirowner=$(stat -c %g $(dirname "${file}"))
              install /dev/null -g $dirowner -m 0664 "${file}"
            fi
            chown root "${file}"
            chmod g+w "${file}"
          '') dynamicMapFiles));

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
        "f /etc/local/mail/users.json 0664 postfix service - {}"
        "f /etc/local/mail/main.cf 0664 postfix service"
      ];

    }))

    (lib.mkIf (svc.enable && config.services.telegraf.enable &&
               role.domains != []) {
      flyingcircus.services.telegraf.inputs.postfix = [{
        queue_directory = "/var/lib/postfix/queue";
      }];

      # This is a hack. Postfix seems to create subdirs in its queue directories
      # which always lack group and other access bits. So we set up our access
      # policies on an ongoing basis.
      systemd.services.postfix-queue-perms =
      let
        dirs = "/var/lib/postfix/queue/{active,hold,incoming,deferred,maildrop}";
      in rec {
        after = [ "postfix.service" ];
        requires = after;
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ acl inotify-tools ];
        script = ''
          fix() {
            setfacl -Rm u:telegraf:rX ${dirs}
            setfacl -Rdm u:telegraf:rX ${dirs}
            sleep 1
          }

          fix
          while true; do
            inotifywait -q -r -e create /var/lib/postfix/queue
            fix
          done
        '';
        serviceConfig = {
          RestartSec = 5;
          Restart = "always";
        };
      };
    })
  ];
}
