import ./make-test-python.nix ({ ... }:
{
  name = "psi";
  nodes = {
    machine = { lib, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      config = {
      };
    };
    machinecgroup = { lib, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      config = {
        flyingcircus.services.telegraf.psiCgroupRegex = [ ".*\\.service" ];
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
      machinecgroup.wait_until_succeeds("curl machine:9126 | grep psi")
      machinecgroup.succeed("curl machine:9126 | grep cgroup")

  '';
}