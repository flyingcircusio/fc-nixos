{ config, lib, pkgs, ... }:

with builtins;
with lib;

# Explanation of various host names:
# - fqdn: "raw" machine name. Points to the srv address which is usually not
#   reachable from the outside but occasionally used for locally generated mail
#   (e.g., cron)
# - mailHost: HELO name
# - domains: list of mail domains for which regular mail accounts exist

let
  inherit (import ../../../versions.nix { }) nixos-mailserver;

  copyToStore = pathString:
    let p = builtins.path { path = pathString; }; in "${p}";

  role = config.flyingcircus.roles.mailserver;
  svc = config.flyingcircus.services.mail;
  fclib = config.fclib;
  primaryDomainCandidates = attrNames (filterAttrs (domain: config: config.enable && config.primary) role.domains);
  primaryDomain =
    if primaryDomainCandidates != []
    then head primaryDomainCandidates
    else "example.org";
  domains = (attrNames (filterAttrs (domain: config: config.enable) role.domains));
  vmailDir = "/srv/mail";
  fallbackGenericVirtual = ''
    postmaster@${primaryDomain} root@${role.mailHost}
    abuse@${primaryDomain} root@${role.mailHost}
  '';
  userAliases =
    concatMapStringsSep "\n"
      (e: "${e.uid}: ${concatStringsSep ", " e.email_addresses}")
      config.flyingcircus.users.userData;

in {
  imports = [
    "${nixos-mailserver}"
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
    # The way we use the mapFiles attribute has a collision potential on files
    # with the same name in different paths. To avoid this, we hash the
    # path and suffix the basename with the hash. This will not cause reloads
    # if the content changes! (PL-132088)
    dynamicMapHash = p: "${baseNameOf p}-${substring 0 8 (hashString "sha1" p)}";
  in lib.mkMerge [
    (lib.mkIf (domains != []) {
      assertions = [
        {
          assertion = builtins.length primaryDomainCandidates == 1;
          message = ''
            It is required that there is exactly one primary domain.
            Set flyingcircus.roles.mail.domains."domain".primary = true; for exactly one domain.
          '';
        }
      ];
    })

    (lib.mkIf svc.enable {
      environment.etc."local/mail/README.txt".source = ./README;
    })

    (lib.mkIf svc.enable {

      flyingcircus.localConfigDirs.mail = {
        dir = "/etc/local/mail/";
        user = "root";
      };

      environment.etc = {
        "local/mail/config.json.example".text = (toJSON {
          domains = {
            "${primaryDomain}" = {
              enable = true;
              primary = true;
            };
            "subdomain.${primaryDomain}" = {
              enable = true;
              autoconfig = false;
            };
          };
          mailHost = "mail.${primaryDomain}";
          webmailHost = "webmail.${primaryDomain}";
          dynamicMaps = { transport = [ "/etc/local/mail/transport" ]; };
        });

        # refer to the source for a comprehensive list of options:
        # https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/default.nix
        # generate password with `mkpasswd -m yescrypt PASSWD` and put it either
        # here (read-only) or into passwdFile (user-changeable)
        "local/mail/users.json.example".text = (toJSON {
          "user@${primaryDomain}" = {
            hashedPassword = "(use 'mkpasswd -m yescrypt PASSWORD')";
            aliases = [ "user1@${primaryDomain}" ];
            quota = "4G";
            sieveScript = null;
            catchAll = [ "subdomain.${primaryDomain}" ];
          };
        });
      };
    })

    (lib.mkIf (svc.enable && domains != []) (
    let
      fqdn = with config.networking; "${hostName}.${domain}";
    in {
      assertions = [
        # at least one needs to be null
        { assertion = role.imprintUrl == null || role.imprintText == null;
          message = ''
            The options imprintUrl and imprintText are mutually exclusive
            Remove one to fix this issue
          '';
        }
        # either not equal or no imprint options used
        { assertion = role.mailHost != role.webmailHost || (role.imprintUrl == null && role.imprintText == null);
          message = ''
            imprintUrl/imprintText cannot be set when webmail is already being served under ${role.mailHost}
            Change webmailHost or remove imprint
          '';
        }
      ];

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
        plug = "${pkgs.monitoring-plugins}/bin";
        mailq = "${pkgs.postfix}/bin/mailq";
        checkMailq = "${pkgs.fc.check-postfix}/bin/check_mailq";
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

      flyingcircus.passwordlessSudoPackages = [
        {
          commands = [ "bin/check_mailq" ];
          package = pkgs.fc.check-postfix;
          groups = [ "sensuclient" ];
        }
      ];

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [ "ALL" ];
          groups = [ "sudo-srv" ];
          runAs = "vmail";
        }
      ];

      # SNM specific configuration, see
      # https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/default.nix
      mailserver = {
        enable = true;
        inherit domains;
        fqdn = role.mailHost;
        loginAccounts = fclib.jsonFromFile "/etc/local/mail/users.json" "{}";
        extraVirtualAliases =
          fclib.jsonFromFile "/etc/local/mail/local_valiases.json" "{}";
        certificateScheme = 3;
        enableImapSsl = true;
        enableManageSieve = true;
        lmtpSaveToDetailMailbox = "no";
        mailDirectory = vmailDir;
        mailboxes = {
          "Trash" = { auto = "create"; specialUse = "Trash"; };
          "Junk" = { auto = "subscribe"; specialUse = "Junk"; };
          "Drafts" = { auto = "subscribe"; specialUse = "Drafts"; };
          "Sent" = { auto = "subscribe"; specialUse = "Sent"; };
          "Archives" = { auto = "subscribe"; specialUse = "Archive"; };
        };
        policydSPFExtraConfig = let
          skipped = [
            "127.0.0.0/8"
            "::ffff:127.0.0.0/104"
            "::/64"
          ] ++ role.policydSPFExtraSkipAddresses;
        in ''
          skip_addresses = ${concatStringsSep "," skipped}
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

      flyingcircus.services.nginx.virtualHosts =
        let
          cfgForDomain = domain:
          nameValuePair "autoconfig.${domain}" {
            addSSL = true;
            enableACME = true;
            locations."=/mail/config-v1.1.xml".alias = (import ./autoconfig.nix {
              inherit domain pkgs lib;
              inherit (role) mailHost webmailHost;
            });
          };
        in listToAttrs ((map cfgForDomain (attrNames (filterAttrs (domain: config: config.enable && config.autoconfig) role.domains))) ++
          (optional (role.imprintUrl != null || role.imprintText != null ) (lib.nameValuePair role.mailHost
            (lib.mkMerge [
              {
                serverName = role.mailHost;
                forceSSL = true;
                enableACME = true;
              }
              (lib.mkIf (role.imprintUrl != null) {
                locations."/".return = "302 ${role.imprintUrl}";
              })
              (lib.mkIf (role.imprintText != null) {
                root = with pkgs; writeTextDir "index.html" role.imprintText;
              })
            ])))
          ++
            (optional (role.imprintUrl == null && role.imprintText == null && role.webmailHost != null && role.webmailHost != role.mailHost)
              (lib.nameValuePair role.mailHost
                {
                  forceSSL = true;
                  enableACME = true;
                  locations."/".return = "302 https://${role.webmailHost}";
                }
              )
            )
          );

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
          smtpd_tls_mandatory_protocols = lib.mkForce ">=TLSv1.2";
          smtpd_tls_protocols = lib.mkForce ">=TLSv1.2";
          smtp_tls_mandatory_protocols = lib.mkForce ">=TLSv1.2";
          smtp_tls_protocols = lib.mkForce ">=TLSv1.2";
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
          # The map files need to be in the store to ensure that they
          # properly trigger reloads when their content changes.
          value = copyToStore path;
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
          optionals (domains != []) (domains ++ [ role.mailHost fqdn ]);
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

      systemd.services.postfix.serviceConfig.ExecReload = lib.mkOverride 50 (
        pkgs.writeScript "postfix-reload" ''
          #! ${pkgs.stdenv.shell} -e
          # Include pre-start script here to have maps regenerated:
          ${config.systemd.services.postfix.preStart}

          ${pkgs.postfix}/bin/postfix reload
        '');

      systemd.tmpfiles.rules = [
        "f ${role.passwdFile} 0660 vmail service"
        "d /etc/local/mail 02775 postfix service"
        "f /etc/local/mail/local_valiases.json 0664 postfix service - {}"
        "f /etc/local/mail/users.json 0664 postfix service - {}"
        "f /etc/local/mail/main.cf 0664 postfix service"
      ];

    }))

    (lib.mkIf (svc.enable && config.services.telegraf.enable &&
               domains != []) {
      flyingcircus.services.telegraf.inputs.postfix = [{
        queue_directory = "/var/lib/postfix/queue";
      }];

      systemd.services.postfix-queue-perms =
      let
        dirs = "/var/lib/postfix/queue/{active,hold,incoming,deferred,maildrop}";
      in rec {
        after = [ "postfix-setup.service" ];    # Ordering
        wantedBy = [ "postfix-setup.service" ]; # Startup, without failure propagation
        partOf = [ "postfix-setup.service" ];   # Restart, without failure propagation
        path = with pkgs; [ acl ];
        script = ''
          setfacl -Rm u:telegraf:rX ${dirs}
          setfacl -Rdm u:telegraf:rX ${dirs}
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

      };
    })
  ];
}
