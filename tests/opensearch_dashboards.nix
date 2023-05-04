import ./make-test-python.nix ({ pkgs, testlib, ... }:
let
  ipv4 = testlib.fcIP.srv4 1;
in
{
  name = "opensearch-dashboards";

  nodes.machine =
    { pkgs, config, lib, ... }:
    {

      imports = [
        (testlib.fcConfig { net.fe = false; })
      ];

      networking.domain = "test";
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = lib.mkForce 2000;
      virtualisation.qemu.options = [ "-smp 2" ];
      flyingcircus.roles.opensearch.enable = true;
      flyingcircus.roles.opensearch.nodes = [ "machine" ];
      flyingcircus.roles.opensearch_dashboards.enable = true;
      systemd.services.opensearch-dashboards.serviceConfig.TimeoutStartSec = 900;
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("opensearch")
    machine.wait_for_unit("opensearch-dashboards")

    status_check = """
      for count in {0..100}; do
        echo "Checking..." | logger -t opensearch-dashboards-status
        curl -s "${ipv4}:5601/api/status" | grep -q '"state":"green' && exit
        sleep 5
      done
      echo "Failed" | logger -t opensearch-dashboards-status
      curl -s "${ipv4}:5601/api/status"
      exit 1
    """

    with subtest("Opensearch dashboards status check should pass"):
        machine.succeed(status_check)

    with subtest("killing the opensearch-dashboards process should trigger an automatic restart"):
        machine.succeed(
            "kill -9 $(systemctl show opensearch-dashboards.service --property MainPID --value)"
        )
        machine.wait_for_unit("opensearch-dashboards")
        machine.succeed(status_check)
  '';
})
