# It's hard to test the real functionality because the updater needs internet
# access and the daemon need large binary files in order to run. We just check
# the generated config.
import ./make-test.nix ({ lib, ... }:
let
  ipv4 = "192.168.101.1";
  ipv6 = "2001:db8:f030:1c3::1";
in {
  name = "antivirus";
  machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.antivirus.enable = true;
      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
            "2001:db8:f030:1c3::/64" = [ ipv6 ];
          };
          gateways = {};
        };
      };
    };

  testScript =
  let
    check = ipaddr: ''
      $machine->succeed('grep ${ipaddr} /etc/clamav/clamd.conf');
    '';
  in ''
    $machine->succeed('systemctl cat clamav-daemon.service');
    $machine->succeed('systemctl cat clamav-freshclam.service');
    $machine->succeed('systemctl cat clamav-freshclam.timer');
  '' + lib.concatMapStrings check [ "127.0.0.1" "::1" ipv4 ipv6 ];
})
