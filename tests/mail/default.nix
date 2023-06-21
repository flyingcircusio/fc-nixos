import ../make-test-python.nix ({pkgs, lib, ...}:
let
  commonConfig = {
    networking.domain = "example.local";
    networking.nameservers = [ "127.0.0.1" ];
    services.dnsmasq.enable = true;
    services.dnsmasq.settings = {
      mx-host = [
        "example.local,mail.example.local"
        "external.local,ext.example.local"
      ];
      no-resolv = true;
      server= [
        "/local/127.0.0.1"
        "/net/"
        "/org/"
        "/com/"
      ];
      address = "/webmail.example.local/192.168.1.3";
    };
    services.haveged.enable = true;
  };
in
{
  name = "mailserver";
  nodes = {
    mail =
      { lib, ... }: {
        imports = [ ../../nixos ../../nixos/roles ];
        config = lib.mkMerge [
          commonConfig
          {
            virtualisation.memorySize = 2048;

            flyingcircus.roles.mailserver = {
              enable = true;
              mailHost = "mail.example.local";
              webmailHost = "webmail.example.local";
              domains = {
                "example.local" = {
                  primary = true;
                };
              };
              rootAlias = "user2@example.local";
            };

            flyingcircus.roles.postgresql14.enable = true;

            virtualisation.vlans = [ 1 3 ];

            flyingcircus.enc.parameters = {
              resource_group = "test";
              interfaces.srv = {
                mac = "52:54:00:12:03:03";
                bridged = false;
                networks = {
                  "192.168.3.0/24" = [ "192.168.3.3" ];
                  "2001:db8:3::/64" = [ "2001:db8:3::3" ];
                };
                gateways = {};
              };
              interfaces.fe = {
                mac = "52:54:00:12:01:03";
                bridged = false;
                networks = {
                  "192.168.1.0/24" = [ "192.168.1.3" ];
                  "2001:db8:1::/64" = [ "2001:db8:1::3" ];
                };
                gateways = {};
              };
            };

            mailserver.certificateScheme = lib.mkOverride 50 2;
            mailserver.loginAccounts = lib.mkForce {
              "user1@example.local" = {
                # User1User1
                hashedPassword = "$5$ld7g3N1MtrZl$PisX9yQsemPEwVNUqQVToe07MaP9qDesXMh5mAwWTR6";
                aliases = [ "alias1@example.local" ];
              };
              "user2@example.local" = {
                # User2USer2
                hashedPassword = "$6$ubISDRB4Pr3IV0CO$n5tZuntp4EG9l6euyyzuR3GQHKcjpzN5f4HRIQrhykuI3H8/6A7H8mS7AFtOR5KZyWeJNX1BGkbetLCZM6A02/";
              };
            };

            # avoid time-consuming generation
            systemd.services.dhparams-gen-dovecot2.script = lib.mkForce ''
              mkdir -p /var/lib/dhparams
              cat > /var/lib/dhparams/dovecot2.pem <<_EOT_
              -----BEGIN DH PARAMETERS-----
              MIIBCAKCAQEA46Obr4INGWek+Ngo+f3Pew34jsXHMPI5gaLwf901wbm18FGgp0Nu
              f91t6beKYJrc+2E63R3E6E26+jY8fo6R4hh7wXtMEb94MyAJ8+fdyNpOGgNko2gf
              c+kuTqgw/wGXZo2k9Zbd/vqTUS1rFR6GuqL6Urb6VAqi2aSFiJfbuE5XJrne9SP4
              j+zSYwtr9mJZHikes6wOs1v5Fkt/ZvKEvlUEfn/nWNnr9xVqBQp7amZullkEHh4r
              F5V/qvJRsppwxaWQWWhcTP/u7GnJBrpQXaQKgDwH9uOwy/hleuRGtfhgIADuWDma
              GT0F+r7c94IjRNKnMd5PdJybaH3xAj+aSwIBAg==
              -----END DH PARAMETERS-----
              _EOT_
            '';

            # conflicts with dnsmasq
            services.kresd.enable = lib.mkForce false;

            # LEC is not able to call remote services
            services.nginx.virtualHosts."autoconfig.example.local" = {
              addSSL = lib.mkForce false;
              enableACME = lib.mkForce false;
            };

            # ... but build the package at least
            environment.systemPackages = [ pkgs.knot-dns ];
          }
        ];
      };
    client =
      { lib, ... }: {
        imports = [ ../../nixos ../../nixos/roles ];
        config = lib.mkMerge [
          commonConfig
          {
            flyingcircus.services.nullmailer.enable = true;

            virtualisation.vlans = [ 1 3 ];

            flyingcircus.enc.parameters.interfaces.srv = {
              mac = "52:54:00:12:03:01";
              bridged = false;
              networks = {
                "192.168.3.0/24" = [ "192.168.3.1" ];
                "2001:db8:3::/64" = [ "2001:db8:3::1" ];
              };
              gateways = {};
            };

            flyingcircus.enc.parameters.interfaces.fe = {
              mac = "52:54:00:12:01:01";
              bridged = false;
              networks = {
                "192.168.1.0/24" = [ "192.168.1.1" ];
                "2001:db8:1::/64" = [ "2001:db8:1::1" ];
              };
              gateways = {};
            };

            flyingcircus.encServices = [
              {
                service = "mailout-mailout";
                address = "mail";
              }
            ];
          }
        ];
      };
    ext =
      { pkgs, ... }: {
        config = lib.mkMerge [
          commonConfig
          {
            networking.firewall.allowedTCPPorts = [ 25 ];
            systemd.services.mailhog =
            let mailHog = "${pkgs.mailhog}/bin/MailHog";
            in {
              description = "MailHog service";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "simple";
                PreStart = "install -d /tmp/mh";
                ExecStart =
                  "${mailHog} -maildir-path /tmp/mh " +
                  "-smtp-bind-addr 0.0.0.0:25 -storage maildir";
              };
            };
          }
        ];
    };
  };
  testScript = let
    passwdFile = "/var/lib/dovecot/passwd";
    chpasswd = "${pkgs.fc.roundcube-chpasswd}/bin/roundcube-chpasswd";
  in ''
    with subtest("postsuper sudo rule should be present for service group"):
      mail.succeed('grep %service /etc/sudoers | grep -q postsuper')

    with subtest("postsuper sudo rule should be present for sudo-srv group"):
      mail.succeed('grep %sudo-srv /etc/sudoers | grep -q postsuper')

    with subtest("roundcube-chpasswd sudo rule should be present for roundcube user"):
      roundcube_sudo = mail.succeed('grep roundcube-chpasswd /etc/sudoers').strip().split()
      assert roundcube_sudo == [
        "roundcube",
        "ALL=(vmail)",
        "NOPASSWD:",
        "${chpasswd}",
      ], f"Got unexpected sudo line: {roundcube_sudo}"

    with subtest("changing a mail password via roundcube-chpasswd should work"):
      mail.succeed("echo user1@example.local:placeholder > ${passwdFile}")
      mail.succeed(
        "sudo -u roundcube "
        "sudo -u vmail ${chpasswd} "
        "${passwdFile} "
        "<<< 'user1@example.local:pass'"
      )
      mail.succeed("grep user1@example.local: ${passwdFile}")
      mail.succeed("grep -v :placeholder ${passwdFile}")

    mail.wait_for_unit('network-online.target')

    with subtest("roundcube webmailer should work"):
      mail.wait_for_unit("phpfpm-roundcube.service")
      mail.succeed("sudo -u roundcube psql -c 'select from users;'")
      mail.succeed("curl webmail.example.local")

    client.wait_for_unit('network-online.target')
    ext.wait_for_unit('network-online.target')

    mail.execute('rm -rf /srv/mail/example.local')
    mail.wait_for_file('/run/rspamd/rspamd-milter.sock')
    mail.wait_for_open_port(25)
    # potential race condition - cf files will be created asynchronously
    mail.wait_for_file('/etc/postfix/main.cf')
    mail.wait_for_file('/etc/postfix/virtual.db')
    client.wait_for_unit('dnsmasq')
    client.sleep(1)

    print("### SMTP incoming to users and (root) aliases ###\n")
    client.succeed('echo | mail -s testmail1 user1@example.local')
    client.succeed('echo | mail -s testmail2 user2@example.local')
    client.succeed('echo | mail -s testmail3 alias1@example.local')
    client.succeed('echo | mail -s testmail4 root')
    client.succeed('echo | mail -s testmail6 user1+detail@example.local')
    mail.succeed('echo | mail -s testmail5 root')
    mail.wait_until_succeeds(
      'test `ls /srv/mail/example.local/user1/new/* | wc -l` == 3')
    # check simple delivery
    mail.succeed('grep testmail1 /srv/mail/example.local/user1/new/*')
    # check alias
    mail.succeed('grep testmail3 /srv/mail/example.local/user1/new/*')
    # check address detail
    mail.succeed('grep testmail6 /srv/mail/example.local/user1/new/*')
    mail.succeed('fgrep "Delivered-To: user1+detail@" /srv/mail/example.local/user1/new/*')
    mail.wait_until_succeeds(
      'test `ls /srv/mail/example.local/user2/new/* | wc -l` == 3')
    # check simple delivery
    mail.succeed('grep testmail2 /srv/mail/example.local/user2/new/*')
    # check root alias
    mail.succeed('grep testmail4 /srv/mail/example.local/user2/new/*')
    # check root delivery on mail server
    mail.succeed('grep testmail5 /srv/mail/example.local/user2/new/*')

    print("### IMAP ###\n")
    mail.wait_for_open_port(143)
    client.succeed('python3 ${./test_imap.py}')

    print("### SMTP outgoing ###\n")
    ext.execute('rm -f /tmp/mh/*')
    ext.wait_for_open_port(25)
    mail.succeed('echo | mail -s testmail6 user1@external.local')
    ext.wait_until_succeeds('ls /tmp/mh/*')
    ext.succeed("fgrep 'HELO:<mail.example.local>\n"
      "FROM:<root\@mail.example.local>\nTO:<user1\@external.local>' /tmp/mh/*")

    print("### Relaying & SMTP AUTH ###\n")
    ext.execute('rm -f /tmp/mh/*')
    client.succeed('python3 ${./test_smtpauth.py}')
    ext.wait_until_succeeds('ls /tmp/mh/*')
    ext.succeed("fgrep 'Subject: testmail7' /tmp/mh/*")
    ext.succeed("""
        fgrep 'DKIM-Signature: v=1; a=rsa-sha256;
        c=relaxed/simple; d=example.local;' /tmp/mh/*
        """)
    ext.succeed("egrep 'Message-Id: <.*\@mail\.example\.local>' /tmp/mh/*")

    client.shutdown()
    mail.shutdown()
    ext.shutdown()
  '';
})
