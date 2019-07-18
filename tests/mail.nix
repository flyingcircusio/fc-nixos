{ system ? builtins.currentSystem
, nixpkgs ? <nixpkgs>
, pkgs ? import ../. {}
}:

with import "${nixpkgs}/nixos/lib/testing.nix" { inherit system; };
with pkgs.lib;

let
  testCases = {
    mailout = {
      name = "mailout";
      nodes.client =
        { lib, ... }:
        {
          imports = [ ../nixos ];
          config = {
            flyingcircus.services.ssmtp.enable = true;
            flyingcircus.encServices = [
              {
                service = "mailout-mailout";
                address = "mailer";
              }
            ];
          };
        };
      nodes.mailer =
        { ... }:
        {
          imports = [ ../nixos ../nixos/roles ];
          flyingcircus.roles.mailout.enable = true;
          flyingcircus.roles.mailserver.hostname = "mailer";
          users.users.foo.isNormalUser = true;
          networking.firewall.allowedTCPPorts = [ 25 ];
        };
      testScript = ''
        startAll;
        $mailer->waitForUnit("postfix.service");

        # test mail delivery
        $client->succeed('echo test mail | mailx -s test foo@mailer');
        $mailer->waitUntilSucceeds('ls /var/spool/mail/foo/new/*.mailer');
        my $m = $mailer->succeed('cat /var/spool/mail/foo/new/*.mailer');
        print($m);
        $m =~ /^From: .*<root\@client>/m or die "no valid 'From:'";
        $m =~ /^To: foo\@mailer/m or die "no valid 'To:'";
        $m =~ /^Subject: test/m or die "no valid 'Subject:'";

        # test SMTP dialogue
        $mailer->succeed(<<_EOT_);
        ${pkgs.monitoring-plugins}/bin/check_smtp -v -H localhost \\
           -C 'MAIL FROM:<root>' -R 250 \\
           -C 'RCPT TO:<foo\@mailer>' -R 250 \\
           -C 'DATA' -R 354 \\
           -C 'Subject: test2\r\n\r\ntest2\r\n.' -R 250
        _EOT_
      '';
    };

    # mailserver = {
    # TBD
    # };
  };

in
mapAttrs
(const (attrs: makeTest (attrs // { name = "mail-${attrs.name}"; })))
testCases
