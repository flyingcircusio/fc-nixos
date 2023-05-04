import ./make-test-python.nix ({ pkgs, lib, testlib, ...} :

with lib;
with testlib;

{
  name = "matomo";

  nodes.machine = { config, pkgs, ... }: {

    imports = [
      (fcConfig { })
    ];

    virtualisation.diskSize = 1024;
    virtualisation.memorySize = 2048;

    networking.domain = "test";

    flyingcircus.roles.matomo = {
      enable = true;
    };

    services.matomo = {
      nginx = {
        forceSSL = false;
        enableACME = false;
      };
    };

    flyingcircus.roles.percona80 = {
      enable = true;
    };

    flyingcircus.roles.mysql.extraConfig = ''
      [mysqld]
      innodb-buffer-pool-size         = 10M
      innodb_log_file_size            = 10M
    '';

    flyingcircus.roles.nginx.enable = true;
  };

  testScript = { nodes, ... }:
  let
    inherit (nodes.machine.services.matomo.tools) matomoConsole matomoCheckPermissions;
    sensuCheck = testlib.sensuCheckCmd nodes.machine;
  in ''
    checks = [
      """${sensuCheck "matomo-permissions"}""",
      """${sensuCheck "matomo-unexpected-files"}""",
      """${sensuCheck "matomo-version"}""",
    ]

    machine.wait_for_unit("mysql.service")
    machine.wait_for_unit("matomo-setup-update.service")
    machine.wait_for_unit("phpfpm-matomo.service")
    machine.wait_for_unit("nginx.service")

    with subtest("nginx user can read image from plugin"):
      machine.succeed("sudo -u nginx stat /var/lib/matomo/share/plugins/CoreHome/images/favicon.ico")

    with subtest("nginx user can read from js dir"):
      machine.succeed("sudo -u nginx stat /var/lib/matomo/share/js/piwik.js")

    with subtest("matomo.js reachable via HTTP"):
      machine.succeed("curl -sSfk http://machine/matomo.js")

    with subtest("js/piwik.js reachable via HTTP"):
      machine.succeed("curl -sSfk http://machine/js/piwik.js")

    with subtest("matomo.php (API) reachable via HTTP"):
      machine.succeed("curl -sSfk http://machine/matomo.php")


    # without the grep the command does not produce valid utf-8 for some reason
    with subtest("Matomo installation shows up"):
        machine.succeed(
            "curl -sSfL http://machine/ | grep '<title>Matomo[^<]*Installation'"
        )

    with subtest("all sensu checks should be green"):
      for check_cmd in checks:
        machine.succeed(check_cmd)

    with subtest("service user can sudo-run matomo-console as matomo user"):
      machine.succeed("sudo -u s-test sudo -nu matomo ${matomoConsole}/bin/matomo-console core:version")

    with subtest("service user can sudo-run matomo-check-permissions"):
      machine.succeed("sudo -u s-test sudo -n ${matomoCheckPermissions}/bin/matomo-check-permissions")

    with subtest("killing the phpfpm process should trigger an automatic restart"):
      machine.succeed("systemctl kill -s KILL phpfpm-matomo")
      machine.sleep(1)
      machine.wait_for_unit("phpfpm-matomo.service")
  '';
})
