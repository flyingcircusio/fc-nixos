import ./make-test.nix ({ pkgs, ... }:
{
  name = "prometheus";
  machine =
    { config, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.statshost-master.enable = true;
      flyingcircus.roles.statshost = {
        hostName = "myself";
        useSSL = false;
      };

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          networks = {
            "192.168.101.0/24" = [ "192.168.101.1" ];
            "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
          };
          gateways = {};
        };
      };

      flyingcircus.encAddresses = [ {
        name = "myself";
        ip = "192.168.101.1";
      } ];
      networking.extraHosts = ''
        192.168.101.1 myself.fcio.net myself
      '';

      services.telegraf.enable = true;  # set in infra/fc but not in infra/testing

      users.users.s-test = {
        isNormalUser = true;
        extraGroups = [ "service" ]; 
      };

    };

  testScript =
    let
      api = "http://192.168.101.1:9090/api/v1";
    in
    ''
      $machine->waitForUnit("prometheus2.service");
      $machine->waitForUnit("telegraf.service");
      $machine->waitForFile("/run/telegraf/influx.sock");

      # Job for RG test created and up?
      $machine->waitUntilSucceeds(<<'EOF');
        curl -s ${api}/targets | \
          jq -e \
          '.data.activeTargets[] |
            select(.health == "up" and .labels.job == "test")'
      EOF

      # Index custom metric, and expect it to be found in prometheus after
      # some time.
      $machine->succeed(<<'EOF');
        echo my_custom_metric value=42 | \
          ${pkgs.socat}/bin/socat - UNIX-CONNECT:/run/telegraf/influx.sock
      EOF

      $machine->waitUntilSucceeds(<<'EOF');
        curl -s ${api}/query?query='my_custom_metric' | \
         jq -e '.data.result[].value[1] == "42"'
      EOF

      # service user should be able to write to local config dir
      $machine->succeed('sudo -u s-test touch /etc/local/statshost/test');
    '';
})
