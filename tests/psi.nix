import ./make-test-python.nix ({ ... }:
{
  name = "psi";
  nodes = {
    machine = { lib, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      config = {
        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:34:57";
            bridged = false;
            networks = {
              "192.168.1.0/24" = [ "192.168.1.1" ];
            };
            gateways = {};
          };
        };
        services.telegraf.enable = true;  # set in infra/fc but not in infra/testing
        
      };
    };
    machinecgroup = { lib, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      config = {
        flyingcircus.services.telegraf.psiCgroupRegex = [ ".*\\.service" ];
        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:34:58";
            bridged = false;
            networks = {
              "192.168.1.0/24" = [ "192.168.1.2" ];
            };
            gateways = {};
          };
        };
        services.telegraf.enable = true;  # set in infra/fc but not in infra/testing        
      };
    };
  };
  testScript = ''
    start_all()
    machines = [machine, machinecgroup]
    for machine in machines:
      machine.wait_for_unit("telegraf.service")
    
    with subtest("psi data should show up and no cgroup data should pop up"):
      machine.wait_until_succeeds("curl machine:9126 | grep psi")
      machine.fail("curl machine:9126 | grep cgroup")
    
    with subtest("psi data should show up and cgroup data should also show up"):
      machinecgroup.wait_until_succeeds("curl machinecgroup:9126 | grep psi")
      machinecgroup.succeed("curl machinecgroup:9126 | grep cgroup")
  '';
})