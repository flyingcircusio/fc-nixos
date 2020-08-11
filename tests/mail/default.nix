import ../make-test.nix ({pkgs, lib, ...}:
let
  commonConfig = {
    networking.domain = "example.local";
    networking.nameservers = [ "127.0.0.1" ];
    services.dnsmasq.enable = true;
    services.dnsmasq.extraConfig = ''
      mx-host=example.local,mail.example.local
      mx-host=external.local,ext.example.local
      no-resolv
      server=/local/127.0.0.1
      server=/net/
      server=/org/
      server=/com/
    '';
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
            flyingcircus.roles.mailserver = {
              enable = true;
              mailHost = "mail.example.local";
              domains = [ "example.local" ];
              rootAlias = "user2@example.local";
            };

            mailserver.loginAccounts = lib.mkForce {
              "user1@example.local" = {
                # User1User1
                hashedPassword = "$5$ld7g3N1MtrZl$PisX9yQsemPEwVNUqQVToe07MaP9qDesXMh5mAwWTR6";
                aliases = [ "alias1@example.local" ];
              };
              "user2@example.local" = {
                # User2USer2
                hashedPassword = "$5$YF.qhP4xh$N.hX/1SMxmjqjYZqmrtTClzzSLOR/scz.TTmz4KAFX2";
              };
            };

            # take some shortcuts in certificate handling for speedy startup
            services.dovecot2.sslServerCert =
              lib.mkForce "/var/lib/acme/mail.example.local/fullchain.pem";
            services.dovecot2.sslServerKey =
              lib.mkForce  "/var/lib/acme/mail.example.local/key.pem";
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

            # ... but build the package at least
            environment.systemPackages = [ pkgs.knot-dns ];
          }
        ];
      };
    client =
      { lib, ... }: {
        imports = [ ../../nixos ];
        config = lib.mkMerge [
          commonConfig
          {
            flyingcircus.services.ssmtp.enable = true;
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
  testScript = ''
    startAll;

    # SMTP incoming to users and (root) aliases
    $mail->execute('rm -rf /srv/mail/example.local/*');
    $mail->waitForOpenPort(25);
    $client->waitForUnit('dnsmasq');
    $client->succeed('echo | mailx -s testmail1 user1@example.local');
    $client->succeed('echo | mailx -s testmail2 user2@example.local');
    $client->succeed('echo | mailx -s testmail3 alias1@example.local');
    $client->succeed('echo | mailx -s testmail4 root');
    $mail->succeed('echo | mailx -s testmail5 root');
    $mail->waitUntilSucceeds(
      'test `ls /srv/mail/example.local/user1/new/* | wc -l` == 2');
    $mail->succeed('grep testmail1 /srv/mail/example.local/user1/new/*');
    $mail->succeed('grep testmail3 /srv/mail/example.local/user1/new/*');
    $mail->waitUntilSucceeds(
      'test `ls /srv/mail/example.local/user2/new/* | wc -l` == 3');
    $mail->succeed('grep testmail2 /srv/mail/example.local/user2/new/*');
    $mail->succeed('grep testmail4 /srv/mail/example.local/user2/new/*');
    $mail->succeed('grep testmail5 /srv/mail/example.local/user2/new/*');

    # IMAP
    $mail->waitForOpenPort(143);
    $client->succeed('python3 ${./test_imap.py}');

    # SMTP outgoing
    $ext->execute('rm -f /tmp/mh/*');
    $ext->waitForOpenPort(25);
    $mail->succeed('echo | mailx -s testmail6 user1@external.local');
    $ext->waitUntilSucceeds('ls /tmp/mh/*');
    $ext->succeed("fgrep 'HELO:<mail.example.local>\n" .
      "FROM:<root\@mail.example.local>\nTO:<user1\@external.local>' /tmp/mh/*");

    # Relaying & SMTP AUTH
    $ext->execute('rm -f /tmp/mh/*');
    $client->succeed('python3 ${./test_smtpauth.py}');
    $ext->waitUntilSucceeds('ls /tmp/mh/*');
    $ext->succeed("fgrep 'Subject: testmail7' /tmp/mh/*");
    $ext->succeed("fgrep 'DKIM-Signature: v=1; a=rsa-sha256; " .
      "c=relaxed/simple; d=example.local;' /tmp/mh/*");
    $ext->succeed("egrep 'Message-Id: <.*\@mail\.example\.local>' /tmp/mh/*");
  '';
})
