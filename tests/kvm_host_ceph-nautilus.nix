import ./make-test-python.nix ({ testlib, useCheckout ? false, testOpts ? "", clientCephRelease ? "nautilus", ... }:
#import ./make-test-python.nix ({ testlib, useCheckout ? true, testOpts ? "-k test_vm_migration_pattern", clientCephRelease ? "nautilus", ... }:
#import ./make-test-python.nix ({ testlib, useCheckout ? true, testOpts ? "", clientCephRelease ? "nautilus", ... }:
#import ./make-test-python.nix ({ testlib, useCheckout ? true, testOpts ? "--flake-finder --flake-runs=500 -x --no-cov", clientCephRelease ? "nautilus", ... }:
with testlib;
let
  getIPForVLAN = vlan: id: "192.168.${toString vlan}.${toString (5 + id)}";
  getIP6ForVLAN = vlan: id: "fd00:1234:000${toString vlan}::${toString (5 + id)}";

  makeHostConfig = { id }:
    { config, pkgs, lib, ... }:
    let
      testPackage = if useCheckout then pkgs.fc.qemu-dev-nautilus else pkgs.fc.qemu-nautilus;
    in
    {

      # We need a lot of RAM specifically if we use the flake finder as due to
      # the amount of operations both Ceph and pytest will pile up memory they
      # can't release between test runs, so this needs to scale.
      virtualisation.memorySize = 8000;
      virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ mgm fe srv sto stb ];
      virtualisation.emptyDiskImages = [ 4000 4000 ];
      imports = [ <fc/nixos> <fc/nixos/roles> ];

      # Use the default flags defined by fc-qemu regardless of
      # what the platform sets or the fc-qemu unit tests will fail.
      flyingcircus.roles.kvm_host.mkfsXfsFlags = null;
      # We want migrations to be slowish so we can test enough code
      # that monitors the migration. Try to push it past 60 seconds.
      flyingcircus.roles.kvm_host.migrationBandwidth = 22500;
      flyingcircus.static.mtus.sto = 1500;
      flyingcircus.static.mtus.stb = 1500;

      flyingcircus.encServices = [
        {
          address = "host1.fcio.net";
          ips = [ (getIP6ForVLAN 3 1) ];
          location = "test";
          service = "consul_server-server";
        }
        {
          address = "host2.fcio.net";
          ips = [ (getIP6ForVLAN 3 2) ];
          location = "test";
          service = "consul_server-server";
        }
        {
          address = "host3.fcio.net";
          ips = [ (getIP6ForVLAN 3 3) ];
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
            ExecStart = "${pkgs.python3Full}/bin/python ${./fakedirectory.py}";
        };
      };

      environment.systemPackages = [
          # Beware: never get the idea to name this script anything that matches
          # "qemu". The tests include a fixture that kills everything with the
          # substring "qemu" in it and naming this script incorrectly can cause
          # the test to kill the test runner itself which in turn causes
          # confusion that may take about 1 hour to figure out what the hell
          # is going on.
          (pkgs.writeShellScriptBin "run-tests" ''
            cd /root/fc.qemu
            export PY_IGNORE_IMPORTMISMATCH=1
            /root/fc.qemu-env/bin/pytest -vv "$@" 2>&1
            ${if testOpts != "" then ''
            # If we run with custom test options we might be filtering
            # for tests and due to the live/not live split either phase
            # might not have any tests. However, we do not want to
            # accidentally accept the `no tests found` failure in Hydra.
            PYTESTRET=$?
            if [ $PYTESTRET -eq 0 ] || [ $PYTESTRET -eq 5 ]; then
              # 5 means no tests found, which might happen if we have options
              true;
            else
              exit $PYTESTRET;
            fi
            '' else ""}
          '')
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

      system.activationScripts.fcQemuSrc = let
        cephPkgs = config.fclib.ceph.mkPkgs "nautilus";
        py = pkgs.python3;
        pyPkgs = py.pkgs;
        qemuTestEnv = py.buildEnv.override {
          extraLibs = [
            testPackage

            # Additional packages to run the tests
            pyPkgs.pytest
            pyPkgs.pytest-xdist
            pyPkgs.pytest-cov
            pyPkgs.mock
            pyPkgs.pytest-timeout

            (pyPkgs.buildPythonPackage rec {
              pname = "pytest-flakefinder";
              version = "1.1.0";

              src = pyPkgs.fetchPypi {
                inherit pname version;
                hash = "sha256-4kEqGSC9uOeQh4OyCz1X6drVkMw5qT6Flv/dSTtAPg4=";
              };

              propagatedBuildInputs = [ pyPkgs.pytest ];

              meta = with lib; {
                description = "Runs tests multiple times to expose flakiness.";
                homepage = "https://github.com/dropbox/pytest-flakefinder";
              };
            })
          ];
          # There are some namespace packages that collide on `backports`.
          ignoreCollisions = true;
        };
      in ''
        # Provide a writable copy so the coverage etc. can be recorded.
        cp -a ${testPackage.src} /root/fc.qemu
        chmod u+w /root/fc.qemu -R
        ln -s ${qemuTestEnv} /root/fc.qemu-env
      '';

      # We need this in the enc files as well so that timer jobs can update
      # the keys etc.
      environment.etc."nixos/services.json".text = builtins.toJSON config.flyingcircus.encServices;

      flyingcircus.roles.ceph_osd = {
        enable = true;
        cephRelease = "nautilus";
      };
      flyingcircus.roles.ceph_mon = {
        enable = true;
        cephRelease = "nautilus";
      };
      flyingcircus.static.ceph.fsids.test.test = "d118a9a4-8be5-4703-84c1-87eada2e6b60";
      flyingcircus.services.ceph.extraSettings = {
            monClockDriftAllowed = 1;
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
      flyingcircus.roles.consul_server.enable = true;
      services.nginx.virtualHosts."host${toString id}.fe.test.fcio.net" = {
        enableACME = lib.mkForce false;
        addSSL = true;
        sslCertificateKey = "/var/self-signed.key";
        sslCertificate = "/var/self-signed.crt";
      };
      system.activationScripts.consul_certificate = ''
        ${pkgs.openssl}/bin/openssl req -nodes -x509 -newkey rsa:4096 -keyout /var/self-signed.key -out /var/self-signed.crt -sha256 -days 365 -subj '/CN=host${toString id}'
      '';

      environment.etc."nixos/enc.json".text = builtins.toJSON {
        name =  "host${toString id}";
        roles = [ "ceph_mon" "ceph_osd" ];
        parameters = {
          directory_password = "password-for-fake-directory";
          directory_url = "http://directory.fcio.net";
          directory_ring = 0;
          location = "test";
          resource_group = "services";
          secret_salt = "salt-for-host-${toString id}-dhkasjy9";
          secrets = { "ceph/admin_key" = "AQBFJa9hAAAAABAAtdggM3mhVBAEYw3+Loehqw==";
                      "consul/encrypt" = "jP68Fxm+m57kpQVYKRoC+lyJ/NcZy7mwvyqLnYm/z1A=";
                      "consul/agent_token" = "ez+W8r+JEywt82Ojin7klSeON97oR6i5rYo3oFxUcLE=";
                      "consul/master_token" = "s+8F8ye9vrq7JvK2OccwnHhf0B/b6qut+oa8NEmYhHs=";
          };
        };
      };

      # Copied from flyingcircus-physical.nix
      networking.firewall.trustedInterfaces = [ "ethsto" "ethstb" "ethmgm" ];

      networking.extraHosts = ''
        ${getIPForVLAN 1 1} host1.mgm.test.fcio.net host1.mgm.test.gocept.net
        ${getIPForVLAN 1 2} host2.mgm.test.fcio.net host2.mgm.test.gocept.net
        ${getIPForVLAN 1 3} host3.mgm.test.fcio.net host2.mgm.test.gocept.net

        ${getIPForVLAN 3 1} directory.fcio.net host1.fcio.net host1
        ${getIPForVLAN 3 2} host2.fcio.net host2
        ${getIPForVLAN 3 3} host3.fcio.net host3

        ${getIP6ForVLAN 3 1} directory.fcio.net host1.fcio.net
        ${getIP6ForVLAN 3 2} host2.fcio.net
        ${getIP6ForVLAN 3 3} host3.fcio.net

        ${getIPForVLAN 4 1} host1.sto.test.ipv4.gocept.net host1.sto.test.gocept.net
        ${getIPForVLAN 4 2} host2.sto.test.ipv4.gocept.net host2.sto.test.gocept.net
        ${getIPForVLAN 4 3} host3.sto.test.ipv4.gocept.net host3.sto.test.gocept.net
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
            "fd00:1234:0001::/48" =  [ (getIP6ForVLAN 1 id) ];
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:02:0${toString id}";
          bridged = true;
          networks = {
            "192.168.2.0/24" = [ (getIPForVLAN 2 id) ];
            "fd00:1234:0002::/48" =  [ (getIP6ForVLAN 2 id) ];
          };
          gateways = {};
        };
        interfaces.srv = {
          mac = "52:54:00:12:03:0${toString id}";
          bridged = true;
          networks = {
            "192.168.3.0/24" = [ (getIPForVLAN 3 id) ];
            "fd00:1234:0003::/48" =  [ (getIP6ForVLAN 3 id) ];
          };
          gateways = {};
        };
        interfaces.sto = {
          mac = "52:54:00:12:04:0${toString id}";
          bridged = false;
          networks = {
            "192.168.4.0/24" = [ (getIPForVLAN 4 id) ];
            "fd00:1234:0004::/48" =  [ (getIP6ForVLAN 4 id) ];
          };
          gateways = {};
        };
        interfaces.stb = {
          mac = "52:54:00:12:08:0${toString id}";
          bridged = false;
          networks = {
            "192.168.8.0/24" = [ (getIPForVLAN 8 id) ];
            "fd00:1234:0008::/48" =  [ (getIP6ForVLAN 8 id) ];
          };
          gateways = {};
        };
      };
    };
in
{
  name = "kvm";
  nodes = {
    host1 = makeHostConfig { id = 1; };
    host2 = makeHostConfig { id = 2; };
    host3 = makeHostConfig { id = 3; };
  };

  testScript = ''
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

    def assert_clean_cluster(host, mons, osds, mgrs, pgs):
      # `osds` can be either of the form `(num_up_osds, num_in_osds)` or a single
      # integer specifying both up and in osds

      try:
        (num_up_osds, num_in_osds) = osds
      except TypeError:
        num_up_osds = osds
        num_in_osds = osds

      global time_waiting
      print("Waiting for clean cluster ...")
      start = time.time()
      # Allow HEALTH_WARN as we do not correctly cover clock skew
      # currently
      tries = 1
      while True:
        status = json.loads(host.execute('ceph -f json-pretty -s')[1])
        # json status is too verbose, but still show the human-readable status
        show(host, 'ceph -s')
        show(host, 'ceph health detail | tail')

        try:
          assert status["health"]["status"] in ['HEALTH_OK', 'HEALTH_WARN']
          assert int(status["monmap"]["num_mons"]) == mons
          osdmap_stat = status["osdmap"]["osdmap"]
          assert osdmap_stat["num_up_osds"] == num_up_osds and \
              osdmap_stat["num_in_osds"] == num_in_osds
          pgstate0 = status["pgmap"]["pgs_by_state"][0]
          assert pgstate0["count"] == pgs and pgstate0["state_name"] == "active+clean"
          assert status["mgrmap"]["available"] and \
              len(status["mgrmap"]["standbys"]) == mgrs-1
          break
        except AssertionError as e:
          if time.time() - start < 60:
            time_waiting += tries*2
            time.sleep(tries*2)
          else:
             raise

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

    host1.wait_for_unit("consul")
    host2.wait_for_unit("consul")
    host3.wait_for_unit("consul")

    time.sleep(5)
    show(host1, "journalctl -u consul")

    wait(show, host1, "consul members")
    wait(show, host2, "consul members")
    wait(show, host3, "consul members")

    host1.wait_for_unit("nginx")
    host2.wait_for_unit("nginx")
    host3.wait_for_unit("nginx")

    ########################################################################
    # NO CEPH INTERACTION - Ceph is not set up properly, yet. Any
    # interaction with Ceph will hang mysteriously!
    ########################################################################

    with subtest("Run unit tests"):
      show(host1, "run-tests ${testOpts} -m 'not live'")

    ########################################################################
    # NO CEPH INTERACTION - Ceph is not set up properly, yet. Any
    # interaction with Ceph will hang mysteriously!
    ########################################################################

    with subtest("Exercise standalone fc-qemu features"):
      result = show(host1, "fc-qemu --help")
      assert result.startswith("usage: fc-qemu"), "Unexpected help output"

      result = show(host1, "fc-qemu ls")
      assert result == "", repr(result)

      result = show(host1, "fc-qemu check")
      assert result == "OK - 0 VMs - 0 MiB used - 0 MiB expected"

      result = show(host1, "fc-qemu report-supported-cpu-models")
      assert "I supported-cpu-model            architecture='x86' description=''' id='qemu64-v1'" in result

      result = show(host1, "fc-qemu-scrub")
      assert "" == result

    with subtest("Initialize first mon"):
      host1.succeed('fc-ceph osd prepare-journal /dev/vdb')
      host1.execute('fc-ceph mon create --size 500m --bootstrap-cluster > /dev/kmsg 2>&1')
      host1.sleep(5)
      host1.succeed('ceph -s > /dev/kmsg 2>&1')
      host1.succeed('fc-ceph keys mon-update-single-client host1 ceph_osd,ceph_mon,kvm_host salt-for-host-1-dhkasjy9')
      host1.succeed('fc-ceph keys mon-update-single-client host2 kvm_host salt-for-host-2-dhkasjy9')

      # mgr keys rely on 'fc-ceph keys' to be executes first
      host1.execute('fc-ceph mgr create --size 500m > /dev/kmsg 2>&1')

    with subtest("Initialize OSD"):
      host1.execute('fc-ceph osd create-bluestore /dev/vdc')
      host1.succeed('ceph osd crush move host1 root=default')

    with subtest("Create pools and images"):
      # The blank RBD pool is required for maintenance operations
      host1.succeed("ceph osd pool create rbd 32")
      host1.succeed("ceph osd pool set rbd size 1")
      host1.succeed("ceph osd pool set rbd min_size 1")
      host1.succeed("ceph osd pool create rbd.ssd 32")
      host1.succeed("ceph osd pool set rbd.ssd size 1")
      host1.succeed("ceph osd pool set rbd.ssd min_size 1")
      host1.succeed("ceph osd pool create rbd.hdd 32")
      host1.succeed("ceph osd pool set rbd.hdd size 1")
      host1.succeed("ceph osd pool set rbd.hdd min_size 1")
      show(host1, "ceph osd lspools")

      # new in jewel: RBD pools are supposed to be initialised
      host1.succeed("rbd pool init rbd.ssd")
      host1.succeed("rbd pool init rbd.hdd")

      host1.succeed("rbd create --size 100 rbd.hdd/fc-21.05-dev")
      host1.succeed("rbd snap create rbd.hdd/fc-21.05-dev@v1")
      host1.succeed("rbd snap protect rbd.hdd/fc-21.05-dev@v1")

    # Let things settle for a bit, otherwise things are in weird
    # intermediate states like pgs not created, time not in sync,
    # mons not accessible, ...
    assert_clean_cluster(host1, 1, 1, 1, 96)

    print("Time spent waiting", time_waiting)

    with subtest("Run integration tests"):
      show(host1, "run-tests ${testOpts} -m 'live'")

    show(host1, "df -h")
    show(host1, "rbd ls rbd.hdd")
    show(host1, "rbd ls rbd.ssd")
    show(host1, "rbd rm rbd/.fc-qemu.maintenance")

    with subtest("Check maintenance enter/exit works"):
      result = show(host1, "/run/current-system/sw/bin/fc-qemu --verbose maintenance enter")
      assert "D enter-maintenance" in result
      assert "D ensure-maintenance-volume" in result
      assert "D creating maintenance volume" in result
      assert "D acquire-maintenance-lock" in result
      assert "I request-evacuation" in result
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

  '';
})
