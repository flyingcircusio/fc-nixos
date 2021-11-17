import ./make-test-python.nix ({ lib, pkgs, ... }:
{
  name = "devhost";
  nodes = {
    devhost =
    { pkgs, config, ... }:
    {
      imports = [ ../nixos ../nixos/roles  ];
      flyingcircus.roles.devhost.enable = true;

      virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ srv fe ];

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:03:01";
          bridged = false;
          networks = {
            "192.168.3.0/24" = [ "192.168.3.1" ];
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:02:01";
          bridged = false;
          networks = {
            "192.168.2.0/24" = [ "192.168.2.1" ];
          };
          gateways = {};
        };
      };
    
    };
  };

  # This is a rather stupid test but it checks that the role works and 
  # that we get the necessary script installed and nginx running.
  # Further tests need hydra and other stuff and we run this from 
  # our releaseXXYYtest machines.
  testScript = ''

    start_all()

    devhost.wait_for_unit("nginx")
    devhost.succeed("which fc-build-dev-container")

  '';

})
