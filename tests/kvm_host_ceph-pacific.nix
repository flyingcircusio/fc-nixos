import ./make-test-python.nix (
  {
    lib,
    testlib,
    useCheckout ? false,
    useFlakefinder ? false,
    testOpts ? "",
    # examples to specify tests
    # "-k mytest"
    # "--flake-finder --flake-runs=500 -x --no-cov"
    # "--setup-show"  # shows which fixtures have been set up / torn down
    clientCephRelease ? "pacific",
    serverCephRelease ? "pacific",
    ...
  }:
  with testlib;
  let
    flakeTestOps = "--flake-finder --flake-runs=9 -x --no-cov -k test_crashed_vm_clean_restart";
    # use some default test opes when running with flake finder
    testOpsToUse = if useFlakefinder && testOps == "" then flakeTestOps else testOpts;
    testTimeout = if useFlakefinder then 25 * 60 * 60 else 40 * 60;
    getIPForVLAN = vlan: id: "192.168.${toString vlan}.${toString (5 + id)}";
    getIP6ForVLAN = vlan: id: "fd00:1234:000${toString vlan}::${toString (5 + id)}";

    makeHostConfig =
      { id }:
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        testPackage =
          if useCheckout then
            pkgs.fc."qemu-dev-${clientCephRelease}"
          else
            pkgs.fc."qemu-${clientCephRelease}";
      in
      {

        # We need a lot of RAM specifically if we use the flake finder as due to
        # the amount of operations both Ceph and pytest will pile up memory they
        # can't release between test runs, so this needs to scale.
        virtualisation.cores = 6;
        virtualisation.writableStore = false;
        virtualisation.useNixStoreImage = true;
        virtualisation.memorySize = 12000;
        virtualisation.diskSize = 10000;
        virtualisation.vlans = with config.flyingcircus.static.vlanIds; [
          mgm
          fe
          srv
          sto
          stb
        ];
        imports = [
          ../nixos
          ../nixos/roles
        ];

        # Use the default flags defined by fc-qemu regardless of
        # what the platform sets or the fc-qemu unit tests will fail.
        flyingcircus.roles.kvm_host.mkfsXfsFlags = null;
        # We want migrations to be slowish so we can test enough code
        # that monitors the migration. Try to push it past 60 seconds.
        flyingcircus.roles.kvm_host.migrationBandwidth = 22500;
        flyingcircus.static.mtus.sto = 1500;
        flyingcircus.static.mtus.stb = 1500;

        # Override some fc-qemu.conf values to match the values expected by tests

        flyingcircus.roles.kvm_host.settings =
          import "${testPackage.testdata}/deployment-settings-overrides.nix"
            { inherit lib; };

        systemd.timers.fc-ceph-load-vm-images.enable = lib.mkForce false;
        systemd.timers.fc-ceph-mon-update-client-keys.enable = lib.mkForce false;
        systemd.timers.fc-ceph-clean-deleted-vms.enable = lib.mkForce false;
        systemd.timers.fc-ceph-purge-old-snapshots.enable = lib.mkForce false;
        systemd.timers.logrotate.enable = lib.mkForce false;

        flyingcircus.encServices = [
          {
            address = "host1.fcio.net";
            ips = [ (getIP6ForVLAN 3 1) ];
            location = "test";
            service = "consul_server-server";
          }
          {
            address = "host1.fcio.net";
            ips = [ (getIPForVLAN 4 1) ];
            location = "test";
            service = "ceph_mon-mon";
          }
        ];

        # DEBUGGING CEPH
        #
        # flyingcircus.roles.ceph_mon.extraSettings = {
        #   logFile = "/dev/console";
        #   debugDefault = "5/5";
        # };
        # flyingcircus.services.ceph.client.extraSettings = {
        #   logFile = "/dev/console";
        #   debugDefault = "5/5";
        #   debugClient = "5/5";
        # };

        systemd.services.fake-directory = rec {
          description = "A fake directory";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = wants;

          environment = {
            PYTHONUNBUFFERED = "1";
          };

          serviceConfig = {
            Type = "simple";
            Restart = "always";
            ExecStart = "${pkgs.python3}/bin/python ${./fakedirectory.py}";
          };
        };

        environment.systemPackages =
          # This is a horrible dance for two reasons:
          # 1. pytest doesn't properly inherit the PATH environment from the propagatedBuildInputs.
          #    We might want to reconsider using an additional buildPythonApplication with pytest
          #    added to the primary dependencies (propagatedBuildInputs)
          # 2. There's a bug(?) in stdenv.mkDerivation that causes external access to the
          #    attribute's items to end up with their .dev outputs ... -_-
          let

            testPackages = (
              [ testPackage ]
              ++ (map (x: builtins.removeAttrs x [ "outputSpecified" ]) testPackage.propagatedBuildInputs)
              ++ testPackage.nativeCheckInputs
            );
            PYTHONPATH = testPackage.py.makePythonPath testPackages;
            PATH = lib.makeBinPath testPackages;
          in
          [
            # Beware: never get the idea to name this script anything that matches
            # "qemu". The tests include a fixture that kills everything with the
            # substring "qemu" in it and naming this script incorrectly can cause
            # the test to kill the test runner itself which in turn causes
            # confusion that may take about 1 hour to figure out what the hell
            # is going on.
            (pkgs.writeShellScriptBin "run-tests" # BEWARE: DO NOT RENAME!
              ''
                set -o pipefail

                export PYTHONPATH="${PYTHONPATH}"
                export PATH="${PATH}:$PATH"
                export PYTHONUNBUFFERED=1

                cd ${testPackage.src}

                rm -f /tmp/fc.qemu-report.xml

                pytest -vv --cov-config=/etc/coveragerc --cov-append -c ${testPackage.src}/pytest.ini "$@" | tee /dev/console

                if ! ${pkgs.gnugrep}/bin/grep -q 'errors="0" failures="0"' /tmp/fc.qemu-report.xml ; then
                  # I've seen weird situations where pytest exited with an error but we exited
                  # with a zero return code. This is a safety-belt. If no report file is there
                  # or the report file shows non-zero errors or failures we return with an error
                  echo "Pytest exit status: $PYTESTRET"
                  echo "Detected failures in unit test report!"
                  exit 1
                else
                  exit 0
                fi
              ''
            )
          ];

        services.openssh.enable = lib.mkForce true;
        environment.etc = {
          "ssh_key" = {
            text = testkey.priv;
            mode = "0400";
          };
          "ssh_key.pub" = {
            text = testkey.pub;
            mode = "0444";
          };
        };
        users.users.root = {
          openssh.authorizedKeys.keys = [
            testkey.pub
          ];
        };

        # We need this in the enc files as well so that timer jobs can update
        # the keys etc.
        environment.etc."nixos/services.json".text = builtins.toJSON config.flyingcircus.encServices;
        environment.etc."coveragerc".text = ''
          [run]
          data_file = /tmp/coverage/data

          [html]
          directory = /tmp/coverage/html
        '';

        flyingcircus.roles.ceph_osd = {
          enable = true;
          cephRelease = serverCephRelease;
        };
        flyingcircus.roles.ceph_mon = {
          enable = if id == 1 then true else false;
          cephRelease = serverCephRelease;
        };
        flyingcircus.static.ceph.fsids.test.test = "d118a9a4-8be5-4703-84c1-87eada2e6b60";
        flyingcircus.services.ceph.extraSettings = {
          monClockDriftAllowed = 10;
          # we do not bootstrap a fully redundant ceph cluster here -> relax replication requirements
          osdPoolDefaultSize = 1;
          osdPoolDefaultMinSize = 1;
          monAllowPoolSizeOne = true;
          monWarnOnPoolNoRedundancy = false;
        };

        # KVM
        flyingcircus.roles.kvm_host = {
          enable = true;
          package = testPackage;
          cephRelease = clientCephRelease;
        };

        environment.sessionVariables = {
          FCQEMU_NO_TTY = "true";
        };

        # Consul
        flyingcircus.roles.consul_server.enable = if id == 1 then true else false;
        services.consul.extraConfig =
          if id == 1 then
            {
              bootstrap_expect = lib.mkForce 1;
            }
          else
            { };
        services.nginx.virtualHosts."host${toString id}.fe.test.fcio.net" = {
          enableACME = lib.mkForce false;
          addSSL = true;
          sslCertificateKey = "/var/run/nginx/self-signed.key";
          sslCertificate = "/var/run/nginx/self-signed.crt";
        };
        systemd.services.nginx.preStart = lib.mkBefore ''
          set -ex
          ${pkgs.openssl}/bin/openssl req -nodes -x509 -newkey rsa:4096 -keyout /var/run/nginx/self-signed.key -out /var/run/nginx/self-signed.crt -sha256 -days 365 -subj '/CN=host${toString id}'
        '';

        environment.etc."simplevm.cfg".text = ''
          name: simplevm
          consul-generation: 0
          parameters:
            cores: 1
            disk: 2
            id: 2345
            interfaces:
              fe:
                mac: aa-bb-cc-00-ee-ff
                networks: {}
                network_number: 2
              srv:
                mac: aa-bb-cc-dd-ee-ff
                networks: {}
                network_number: 3
            kvm_host: host1
            memory: 256
            location: test
            name: simplevm
            online: false
            rbd_pool: rbd.ssd
            resource_group: test
            swap_size: 1073741824
            tmp_size: 5368709120
            environment: fc-21.05-dev
            environment_class: NixOS
            environment_class_type: nixos
        '';
        environment.etc."nixos/enc.json".text = builtins.toJSON {
          name = "host${toString id}";
          roles = [
            "ceph_mon"
            "ceph_osd"
          ];
          parameters = {
            directory_password = "password-for-fake-directory";
            directory_url = "http://directory.fcio.net";
            directory_ring = 0;
            location = "test";
            resource_group = "services";
            # This secret needs to be kept in sync with the fc-qemu test
            # fixtures.
            secret_salt = "salt-for-host-dhkasjy9";
            secrets = {
              "ceph/admin_key" = "AQBFJa9hAAAAABAAtdggM3mhVBAEYw3+Loehqw==";
              "consul/encrypt" = "jP68Fxm+m57kpQVYKRoC+lyJ/NcZy7mwvyqLnYm/z1A=";
              "consul/agent_token" = "ez+W8r+JEywt82Ojin7klSeON97oR6i5rYo3oFxUcLE=";
              "consul/master_token" = "s+8F8ye9vrq7JvK2OccwnHhf0B/b6qut+oa8NEmYhHs=";
            };
          };
        };

        networking.extraHosts = ''
          ${getIPForVLAN 1 1} host1.mgm.test.fcio.net host1.mgm.test.gocept.net
          ${getIPForVLAN 1 2} host2.mgm.test.fcio.net host2.mgm.test.gocept.net

          ${getIPForVLAN 3 1} directory.fcio.net host1.fcio.net host1
          ${getIPForVLAN 3 2} host2.fcio.net host2

          ${getIP6ForVLAN 3 1} directory.fcio.net host1.fcio.net
          ${getIP6ForVLAN 3 2} host2.fcio.net

          ${getIPForVLAN 4 1} host1.sto.test.ipv4.gocept.net host1.sto.test.gocept.net
          ${getIPForVLAN 4 2} host2.sto.test.ipv4.gocept.net host2.sto.test.gocept.net
        '';

        flyingcircus.enc.name = "host${toString id}";
        flyingcircus.enc.parameters = {
          location = "test";
          kvm_net_memory = 2000;
          resource_group = "test";
          # These are keys/tokens explicitly generated to be public and insecure for
          # testing.
          secrets."consul/encrypt" = "jP68Fxm+m57kpQVYKRoC+lyJ/NcZy7mwvyqLnYm/z1A=";
          secrets."consul/agent_token" = "ez+W8r+JEywt82Ojin7klSeON97oR6i5rYo3oFxUcLE=";
          secrets."consul/master_token" = "s+8F8ye9vrq7JvK2OccwnHhf0B/b6qut+oa8NEmYhHs=";
          interfaces.mgm = {
            mac = "52:54:00:12:01:0${toString id}";
            bridged = false;
            networks = {
              "192.168.1.0/24" = [ (getIPForVLAN 1 id) ];
              "fd00:1234:0001::/48" = [ (getIP6ForVLAN 1 id) ];
            };
            gateways = { };
          };
          interfaces.fe = {
            mac = "52:54:00:12:02:0${toString id}";
            bridged = true;
            networks = {
              "192.168.2.0/24" = [ (getIPForVLAN 2 id) ];
              "fd00:1234:0002::/48" = [ (getIP6ForVLAN 2 id) ];
            };
            gateways = { };
          };
          interfaces.srv = {
            mac = "52:54:00:12:03:0${toString id}";
            bridged = true;
            networks = {
              "192.168.3.0/24" = [ (getIPForVLAN 3 id) ];
              "fd00:1234:0003::/48" = [ (getIP6ForVLAN 3 id) ];
            };
            gateways = { };
          };
          interfaces.sto = {
            mac = "52:54:00:12:04:0${toString id}";
            bridged = false;
            networks = {
              "192.168.4.0/24" = [ (getIPForVLAN 4 id) ];
              "fd00:1234:0004::/48" = [ (getIP6ForVLAN 4 id) ];
            };
            gateways = { };
          };
          interfaces.stb = {
            mac = "52:54:00:12:08:0${toString id}";
            bridged = false;
            networks = {
              "192.168.8.0/24" = [ (getIPForVLAN 8 id) ];
              "fd00:1234:0008::/48" = [ (getIP6ForVLAN 8 id) ];
            };
            gateways = { };
          };
        };
      };
  in
  {
    name = "kvm";
    globalTimeout = testTimeout;
    nodes = {
      host1 = makeHostConfig { id = 1; };
      host2 = makeHostConfig { id = 2; };
    };

    testScript =
      { nodes, ... }:
      ''
        import textwrap
        import time
        import json

        time_waiting = 0
        start_all()

        def show(host, cmd):
          print(cmd)
          code, output = host.execute(cmd)
          print(output)
          if code:
            raise RuntimeError(
              f"Command `cmd` failed with exit code {code}")
          return output.strip()

        def wait(fun, *args, **kw):
          global time_waiting
          print(f"Waiting for `{fun.__name__}(*{args}, **{kw})` ...")
          start = time.time()
          tries = 1
          while True:
            try:
              return fun(*args, **kw)
            except Exception:
              if time.time() - start < 60:
                time_waiting += tries*2
                time.sleep(tries*2)
              else:
                raise

        show(host1, "for x in /etc/ceph/*; do echo $x ; cat $x; echo '========='; done")
        host1.execute("systemctl stop fc-ceph-mon")
        host1.execute("systemctl stop fc-ceph-mgr")

        with subtest("fc-qemu-scrub timer is correctly activated"):
          _, output = host1.execute("systemctl list-timers | grep fc-qemu-scrub")
          print(output)
          assert "fc-qemu-scrub" in output
          assert "min left "
          assert not output.startswith("n/a")
          assert output.count("n/a") <= 2

        host1.execute("systemctl stop fc-qemu-scrub.timer")
        host2.execute("systemctl stop fc-qemu-scrub.timer")

        host1.wait_for_unit("consul")
        host2.wait_for_unit("consul")

        wait(show, host1, "consul members")
        wait(show, host2, "consul members")

        host1.wait_for_unit("nginx", timeout=10)

        with subtest("Run tests"):
          host1.succeed("run-tests ${testOpsToUse}", timeout=${toString testTimeout})

        # XXX the following tests should be migrated to fc.qemu at some point
        show(host1, "rbd rm rbd/.fc-qemu.maintenance || true")

        with subtest("Check maintenance enter/exit works"):
          result = show(host1, "/run/current-system/sw/bin/fc-qemu --verbose maintenance enter")
          assert "D enter-maintenance" in result
          assert "D ensure-maintenance-volume" in result
          assert "D creating maintenance volume" in result
          assert "D acquire-maintenance-lock" in result
          assert "I request-evacuation" in result
          assert "maintenance_evacuation_timeout=${toString nodes.host1.flyingcircus.roles.kvm_host.maintenanceEvacuationTimeout}" in result, \
              "maintenance_evacuation_timeout not overridden correctly"
          assert "I evacuation-pending" in result
          assert "I evacuation-running" in result
          assert "I evacuation-success" in result

          result = show(host1, "/run/current-system/sw/bin/fc-qemu --verbose maintenance leave")

          result = show(host1, "/run/current-system/sw/bin/fc-qemu --verbose maintenance enter")
          assert "D enter-maintenance" in result
          assert "D ensure-maintenance-volume" in result
          assert "D creating maintenance volume" not in result
          assert "D acquire-maintenance-lock" in result
          assert "I request-evacuation" in result
          assert "I evacuation-pending" in result
          assert "I evacuation-running" in result
          assert "I evacuation-success" in result

        with subtest("Exercise standalone fc-qemu features"):
          result = show(host1, "fc-qemu --help")
          assert result.startswith("usage: fc-qemu"), "Unexpected help output"

          host1.execute("rm -f /etc/qemu/vm/* /etc/qemu/vm/.*")
          host1.execute("pkill -f qemu")
          host1.execute("rm -rf /run/qemu.*")
          host1.succeed("cp /etc/simplevm.cfg /etc/qemu/vm/")
          host1.succeed("fc-qemu start simplevm")
          result = show(host1, "fc-qemu ls")
          assert "I simplevm              online                         cores=1 memory_booked='256'" in result, repr(result)
          assert "memory_pss='" in result, repr(result)
          assert "memory_swap='0'" in result, repr(result)
          result = show(host1, "fc-qemu check")
          assert "OK - 1 VMs - " in result, result
          assert " MiB used - " in result, result
          assert " MiB expected" in result, result

          result = show(host1, "fc-qemu report-supported-cpu-models")
          assert "I supported-cpu-model            architecture='x86' description=''' id='qemu64-v1'" in result, result

          result = show(host1, "fc-qemu-scrub")
          assert "I simplevm              running-ensure                 generation=0" in result, result

        ${lib.optionalString (!useFlakefinder) ''
          host1.copy_from_vm('/tmp/coverage', './')
          host1.copy_from_vm('/tmp/fc.qemu-report.xml', './')
        ''}

      '';
  }
)
