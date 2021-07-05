import ./make-test-python.nix (
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

          services.telegraf.enable = false;

          users.users.s-svc = {
            inherit home;
            createHome = true;
            isNormalUser = true;
            group = "service";
            uid = 2019;
          };
        };
      };

    testScript = ''
      info = machine.get_unit_info("user-logrotate-s-svc.service")
      assert (info["TriggeredBy"] == "user-logrotate-s-svc.timer"), f"unexpected unit info: {info}"

      machine.succeed("""
          set -e
          echo "hello world" > ${home}/app.log
          chown s-svc: ${home}/app.log
          echo -e "${home}/app.log {\nsize 1\n}" > /etc/local/logrotate/s-svc/app.conf
          """)

      machine.systemctl("start user-logrotate-s-svc.service")

      print(machine.succeed("set -e " +
          # user-logrotate.sh must create control files here
          """
          ls -l /var/spool/logrotate
          test -s /var/spool/logrotate/s-svc.conf
          test -s /var/spool/logrotate/s-svc.state
          """ +
          # test that the logfile has been rotated
          """
          ls -l ${home}
          test -s ${home}/app.log-$(date +%Y%m%d)
          """))
    '';
  }
)
