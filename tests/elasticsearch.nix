import ./make-test-python.nix ({ version ? "7", pkgs, testlib, lib, ... }:
{

  name = "elasticsearch${version}";
  testCases = {

    single = let
      ipv4 = testlib.fcIP.srv4 1;
      ipv6 = testlib.fcIP.srv6 1;
    in
    {
      nodes = {
        machine = { pkgs, config, ... }: {
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
      };

      testScript = { nodes, ... }:
      let
        sensuCheck = testlib.sensuCheckCmd nodes.machine;
      in ''
        import json

        expected_major_version = ${version}

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
            api_result = json.loads(machine.wait_until_succeeds("curl ${ipv4}:9200"))

        with subtest(f"version should be {expected_major_version}.x in the OSS flavor"):
          version_info = api_result["version"]
          major_version = int(version_info["number"][0])
          assert major_version == expected_major_version, f"expected major version {expected_major_version}, got {major_version}"
          build_flavor = version_info["build_flavor"]
          assert build_flavor == "oss", f"expected oss flavor, got {build_flavor}"

        with subtest("service user should be able to write to local config dir"):
          machine.succeed('sudo -u elasticsearch touch /etc/local/elasticsearch/clusterName')

        with subtest("elasticsearch (java) opens expected ports"):
          assert_listen(machine, "java", expected_sockets)

        with subtest("all sensu checks should be green"):
          for check_cmd in checks:
            machine.succeed(check_cmd)

        with subtest("killing the elasticsearch process should trigger an automatic restart"):
          machine.succeed("systemctl kill -s KILL elasticsearch")
          machine.sleep(1)
          machine.wait_until_succeeds("${sensuCheck "es_node_status"}")

        with subtest("status check should be red after shutting down nginx"):
          machine.systemctl('stop elasticsearch')
          machine.wait_until_fails("${sensuCheck "es_node_status"}")
      '';
    };

    multi = {
      nodes = let
        mkESNode = { id, conf ? {}}:
          { pkgs, config, nodes, lib, ... }: {
            imports = [
              (testlib.fcConfig { net.fe = false; inherit id; })
            ];

            networking.domain = "test";
            virtualisation.memorySize = 3072;
            virtualisation.qemu.options = [ "-smp 2" ];
            flyingcircus.roles."elasticsearch${version}".enable = true;
            flyingcircus.roles.elasticsearch = {
              clusterName = "test";
              initialMasterNodes = lib.optionals (version != "6")
                config.flyingcircus.roles.elasticsearch.esNodes;
            };
            flyingcircus.encServices = [
              {
                address = "node1.test";
                service = "elasticsearch${version}-node";
              }
              {
                address = "node2.test";
                service = "elasticsearch${version}-node";
              }
              {
                address = "node3.test";
                service = "elasticsearch${version}-node";
              }
            ];
            networking.firewall.trustedInterfaces = [ "ethsrv" ];
          };
      in
      {
        node1 = mkESNode { id = 1; };
        node2 = mkESNode { id = 2; };
        node3 = mkESNode { id = 3; };
      };

      testScript = ''
        print()
        node1.start()

        ${lib.optionalString (version == "7") ''
          with subtest("ES on node1 should start, waiting for a second node"):
            node1.wait_for_unit("elasticsearch")
            out = node1.wait_until_succeeds("curl node1:9200/_cat/nodes")
            print(out)
            assert "master_not_discovered_exception" in out, "Could not find master_not_discovered_exception in output"
        ''}
        with subtest("starting node2 should form a cluster"):
          node2.wait_for_unit("elasticsearch")
          node2.sleep(2)
          print(node2.succeed("curl node1:9200/_cat/nodes"))
          print(node2.wait_until_succeeds("curl --fail-with-body node2:9200/_cat/nodes"))

        with subtest("node3 should join the existing cluster"):
          node3.wait_for_unit("elasticsearch")
          node3.sleep(2)
          print(node3.wait_until_succeeds("curl --fail-with-body node3:9200/_cat/nodes"))
      '';
    };
  };
})
