import ./make-test.nix (
  let
    home = "/srv/s-svc";
  in
  { pkgs, ... }:
  {
    name = "user-logrotate";
    machine =
      { ... }:
      {
        imports = [ ../nixos ];

        config = {
          flyingcircus.logrotate.enable = true;

          users.users.s-svc = {
            inherit home;
            createHome = true;
            group = "service";
            uid = 2019;
          };
        };
      };

    testScript = ''
      my $info = $machine->getUnitInfo("user-logrotate-s-svc.service");
      $info->{TriggeredBy} eq "user-logrotate-s-svc.timer" or
        die "unexpected unit info: " . $info;

      $machine->succeed(<<_EOT_);
      set -e
      echo "hello world" > ${home}/app.log
      chown s-svc: ${home}/app.log
      echo -e "${home}/app.log {\nsize 1\n}" > /etc/local/logrotate/s-svc/app.conf
      _EOT_

      $machine->systemctl("start user-logrotate-s-svc.service");

      print($machine->succeed(<<_EOT_));
      set -e
      # user-logrotate.sh must create control files here
      ls -l /var/spool/logrotate
      test -s /var/spool/logrotate/s-svc.conf
      test -s /var/spool/logrotate/s-svc.state
      # test that the logfile has been rotated
      ls -l ${home}
      test -s ${home}/app.log-\$(date +%Y%m%d)
      _EOT_
    '';
  }
)
