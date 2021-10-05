import ./make-test-python.nix ({ version ? "7", pkgs, testlib, ... }:
let
  ipv4 = testlib.fcIP.srv4 1;
  ipv6 = testlib.fcIP.srv6 1;
in
{
  name = "elasticsearch";

  machine =
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
      flyingcircus.roles."elasticsearch${version}".enable = true;
      flyingcircus.roles.elasticsearch.esNodes = [ "machine" ];
    };

  testScript = { nodes, ... }:
  let
    sensuCheck = testlib.sensuCheckCmd nodes.machine;
  in ''
    checks = [
      "${sensuCheck "es_node_status"}",
      "${sensuCheck "es_circuit_breakers"}",
      "${sensuCheck "es_cluster_health"}",
      "${sensuCheck "es_file_descriptor"}",
      "${sensuCheck "es_heap"}",
      "${sensuCheck "es_shard_allocation_status"}",
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

    machine.wait_for_unit("elasticsearch")

    with subtest("Elasticsearch API should respond"):
      machine.wait_until_succeeds("curl ${ipv4}:9200")

    with subtest("service user should be able to write to local config dir"):
      machine.succeed('sudo -u elasticsearch touch /etc/local/elasticsearch/clusterName')

    with subtest("elasticsearch (java) opens expected ports"):
      assert_listen(machine, "java", expected_sockets)

    with subtest("all sensu checks should be green"):
      for check_cmd in checks:
        machine.succeed(check_cmd)

    with subtest("killing the elasticsearch process should trigger an automatic restart"):
      machine.succeed("systemctl kill -s KILL elasticsearch")
      machine.sleep(0.5)
      machine.wait_until_succeeds("${sensuCheck "es_node_status"}")

    with subtest("status check should be red after shutting down nginx"):
      machine.systemctl('stop elasticsearch')
      machine.wait_until_fails("${sensuCheck "es_node_status"}")

  '';
})
