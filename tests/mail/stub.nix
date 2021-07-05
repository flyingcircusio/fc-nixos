import ../make-test-python.nix ({pkgs, lib, ...}:
{
  name = "mailstub";
  nodes = {
    mail =
      { lib, ... }: {
        imports = [ ../../nixos ../../nixos/roles ];
        config = {
          flyingcircus.roles.mailstub.enable = true;
          networking.domain = null;

          flyingcircus.enc.parameters = {
            resource_group = "test";
            interfaces.srv = {
              mac = "52:54:00:12:34:56";
              bridged = false;
              networks = {
                "192.168.101.0/24" = [ "192.168.101.1" ];
                "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::3" ];
              };
              gateways = {};
            };
          };

          flyingcircus.enc.parameters.interfaces.fe = {
            mac = "52:54:00:12:35:56";
            bridged = false;
            networks = {
              "192.168.102.0/24" = [ "192.168.102.1" ];
              "2001:db8:f030:1c2::/64" = [ "2001:db8:f030:1c2::3" ];
            };
            gateways = {};
          };

        };
      };
  };
  testScript = ''
    start_all()
    # basic smoke test, should be expanded
    mail.wait_for_open_port(25)
  '';
})
