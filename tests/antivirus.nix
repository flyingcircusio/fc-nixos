# It's hard to test the real functionality because the updater needs internet
# access and the daemon need large binary files in order to run. We just check
# the generated config.
import ./make-test-python.nix ({ lib, testlib, pkgs, ... }:
let
  ipv4 = "192.168.101.1";
  ipv6 = "2001:db8:f030:1c3::1";
in {
  name = "antivirus";
  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.antivirus.enable = true;
      flyingcircus.enc.parameters = {
        resource_group = "test";
        memory = 3072;    #lower limit for allowing the enabling of antivirus
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
            "2001:db8:f030:1c3::/64" = [ ipv6 ];
          };
          gateways = {};
        };
      };
    };

  testScript = { nodes, ... }:
  let
    grepDaemonConfig = searchterm:
      ''machine.succeed("grep '${searchterm}' /etc/clamav/clamd.conf")'';
    grepFreshclamConfig = searchterm:
      ''machine.succeed("grep '${searchterm}' /etc/clamav/freshclam.conf")'';

    dbCheck =
      "PATH=$PATH:${pkgs.monitoring-plugins}/bin "
      + (testlib.sensuCheckCmd nodes.machine "clamav-updater");
  in ''
    with subtest("systemd services should be present"):
      machine.succeed('systemctl cat clamav-daemon.service')
      machine.succeed('systemctl cat clamav-freshclam.service')
      machine.succeed('systemctl cat clamav-init-database.service')

    with subtest("freshclam timer should be active"):
      machine.wait_for_unit('clamav-freshclam.timer')

    with subtest("private mirror should be set up"):
      ${grepFreshclamConfig "PrivateMirror https://clamavmirror.fcio.net"}
      ${grepFreshclamConfig "ScriptedUpdates false"}

    with subtest("listen IP addresses should be configured in daemon config"):
      ${grepDaemonConfig "127.0.0.1"}
      ${grepDaemonConfig "::1"}
      ${grepDaemonConfig ipv4}
      ${grepDaemonConfig ipv6}


    with subtest("sensu database check should be red without database"):
      machine.fail("${dbCheck}")

    with subtest("sensu database check should be green with recent daily file"):
      machine.succeed("touch /var/lib/clamav/main.cld")
      machine.succeed("touch /var/lib/clamav/daily.cld")
      machine.succeed("${dbCheck}")

    with subtest("sensu database check should be red with outdated daily file"):
      machine.succeed("touch -d '3 days ago' /var/lib/clamav/daily.cld")
      machine.fail("${dbCheck}")
  '';

})
