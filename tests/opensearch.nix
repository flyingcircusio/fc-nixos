import ./make-test-python.nix ({ pkgs, testlib, ... }:
let
  ipv4 = testlib.fcIP.srv4 1;
  ipv6 = testlib.fcIP.srv6 1;
in
{
  name = "opensearch";

  nodes.machine =
    { pkgs, config, ... }:
    {
      imports = [
        (testlib.fcConfig { net.fe = false; })
      ];

      networking.domain = "test";
      networking.extraHosts = ''
        ${ipv6} machine.test
      '';
      virtualisation.memorySize = 3072;
      virtualisation.qemu.options = [ "-smp 2" ];
      flyingcircus.roles.opensearch.enable = true;
      flyingcircus.roles.opensearch.nodes = [ "machine" ];
    };

  testScript = { nodes, ... }:
  let
    sensuCheck = testlib.sensuCheckCmd nodes.machine;
  in ''
    import json

    checks = [
      "${sensuCheck "opensearch_node_status"}",
      "${sensuCheck "opensearch_circuit_breakers"}",
      "${sensuCheck "opensearch_cluster_health"}",
      "${sensuCheck "opensearch_heap"}",
      "${sensuCheck "opensearch_shard_allocation_status"}",
    ]

    expected_sockets = [
      "${ipv4}:9200",
      "${ipv6}:9200",
      "${ipv4}:9300",
      "${ipv6}:9300",
    ]

    def assert_listen(machine, process_name, expected_sockets):
      result = machine.succeed(f"netstat -tlpn | grep {process_name} | awk '{{ print $4 }}'")
      actual = set(result.splitlines())
      assert set(expected_sockets) == actual, f"expected sockets: {expected_sockets}, found: {actual}"

    machine.wait_for_unit("opensearch")

    with subtest("opensearch API should respond"):
        api_result = json.loads(machine.wait_until_succeeds("curl ${ipv4}:9200"))
        cluster_name = api_result["cluster_name"]
        assert cluster_name == "machine", f"expected cluster name 'machine', got '{cluster_name}'"

    with subtest("opensearch (java) opens expected ports"):
      assert_listen(machine, "java", expected_sockets)

    with subtest("all sensu checks should be green"):
      for check_cmd in checks:
        machine.succeed(check_cmd)

    with subtest("killing the opensearch process should trigger an automatic restart"):
      machine.succeed("systemctl kill -s KILL opensearch")
      machine.sleep(1)
      machine.wait_until_succeeds("${sensuCheck "opensearch_node_status"}")

    with subtest("status check should be red after shutting down nginx"):
      machine.systemctl('stop opensearch')
      machine.wait_until_fails("${sensuCheck "opensearch_node_status"}")
  '';
})
