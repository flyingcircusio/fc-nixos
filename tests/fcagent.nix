import ./make-test-python.nix ({ pkgs, ... }:
let
  agent_updates_channel_with_maintenance = pkgs.writeScript "agent-updates-channel-with-maintenance" ''
      #!/bin/sh
      set -ex
      x=$(grep ExecStart /etc/systemd/system/fc-agent.service)
      x=''${x/ExecStart=/}
      cat $x
      grep 'channel-with-maintenance' $x
      '';
in
  {
  name = "fc-agent";
  nodes = {
    prod =
      { config, lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.agent.enable = true;
        flyingcircus.enc.parameters.production = true;

        flyingcircus.enc.parameters.interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ "192.168.101.1" ];
            "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
          };
          gateways = {};
        };

      };

    nonprod =
      { config, lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.agent.enable = true;
        flyingcircus.enc.parameters.production = false;

        flyingcircus.enc.parameters.interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ "192.168.101.1" ];
            "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
          };
          gateways = {};
        };

      };

  };
  testScript = ''
    nonprod.wait_for_unit('multi-user.target')
    nonprod.fail('${agent_updates_channel_with_maintenance}')

    prod.wait_for_unit('multi-user.target')
    prod.succeed('${agent_updates_channel_with_maintenance}')
  '';
})

