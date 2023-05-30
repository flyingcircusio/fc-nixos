# Taken from NixOS 22.11, see pkgs/solr/COPYING.md

import ./make-test-python.nix ({ pkgs, testlib, ... }:

{
  name = "solr";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        (testlib.fcConfig { net.fe = false; })
      ];
      # Ensure the virtual machine has enough memory for Solr to avoid the following error:
      #
      #   OpenJDK 64-Bit Server VM warning:
      #     INFO: os::commit_memory(0x00000000e8000000, 402653184, 0)
      #     failed; error='Cannot allocate memory' (errno=12)
      #
      #   There is insufficient memory for the Java Runtime Environment to continue.
      #   Native memory allocation (mmap) failed to map 402653184 bytes for committing reserved memory.
      virtualisation.memorySize = 2000;

      services.solr.enable = true;
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("solr.service")
    machine.wait_for_open_port(8983)
    machine.succeed("curl --fail http://localhost:8983/solr/")

    # adapted from pkgs.solr/examples/films/README.txt
    machine.succeed("sudo -u solr solr create -c films")
    machine.succeed("chmod 0644 /var/lib/solr/data/films/conf/managed-schema")
    res = machine.succeed(
        """
      curl http://localhost:8983/solr/films/schema -X POST -H 'Content-type:application/json' --data-binary '{
        "add-field" : {
          "name":"name",
          "type":"text_general",
          "multiValued":false,
          "stored":true
        },
        "add-field" : {
          "name":"initial_release_date",
          "type":"pdate",
          "stored":true
        }
      }'
    """
    )

    assert '"status":0' in res, "unexpected output: " + res

    machine.succeed(
        "sudo -u solr post -c films ${pkgs.solr}/example/films/films.json"
    )
    assert '"name":"Batman Begins"' in machine.succeed(
        "curl http://localhost:8983/solr/films/query?q=name:batman"
    )
  '';
})
