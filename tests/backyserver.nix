import ./make-test-python.nix ({ pkgs, lib, testlib, clientCephRelease, ... }:
let
  hostIDs = lib.range 1 1;

  generateServices = id:
    builtins.concatMap (host: [
        {
          service = "backyserver-sync";
          address = "host${toString host}.fcio.net";
          location = "test";
          password = "from-${toString id}-to-${toString host}";
          ips = [ (testlib.fcIP.sto6 host)];
        }
        {
          service = "consul_server-server";
          address = "host${toString host}.fcio.net";
          location = "test";
          ips = [ (testlib.fcIP.srv6 host) ];
        }
      ]
    ) hostIDs;

  generateServiceClients = id:
    map (host:
      {
        service = "backyserver-sync";
        location = "test";
        node = "host${toString host}.fcio.net";
        password = "from-${toString host}-to-${toString id}";
      }
    ) hostIDs;

  makeHostConfig = { id }:
    { config, ... }:
    {
      imports = [
        (testlib.fcConfig {
          inherit id;
          # net.fe = false;
          net.sto = true;
          net.stb = true;
          extraEncParameters = {
            kvm_net_memory = 2000;
            directory_password = "password-for-fake-directory";
            directory_url = "http://directory.fcio.net";
            directory_ring = 0;
            secret_salt = "salt-for-host-${toString id}-dhkasjy9";
            secrets = {
              "consul/encrypt" = "jP68Fxm+m57kpQVYKRoC+lyJ/NcZy7mwvyqLnYm/z1A=";
              "consul/agent_token" = "ez+W8r+JEywt82Ojin7klSeON97oR6i5rYo3oFxUcLE=";
              "consul/master_token" = "s+8F8ye9vrq7JvK2OccwnHhf0B/b6qut+oa8NEmYhHs=";
              "ceph/admin_key" = "AQBFJa9hAAAAABAAtdggM3mhVBAEYw3+Loehqw==";
            };
          };
        })
      ];

      virtualisation.memorySize = 3000;
      virtualisation.emptyDiskImages = [ 4000 4000 ];

      flyingcircus.static.mtus.sto = 1500;
      flyingcircus.static.mtus.stb = 1500;

      flyingcircus.roles.backyserver = {
        enable = true;
        cephRelease = clientCephRelease;
      };
      flyingcircus.roles.ceph_osd = {
        enable = true;
        cephRelease = clientCephRelease;
      };
      flyingcircus.roles.ceph_mon = {
        enable = true;
        cephRelease = clientCephRelease;
      };
      flyingcircus.static.ceph.fsids.test.test = "d118a9a4-8be5-4703-84c1-87eada2e6b60";
      flyingcircus.services.ceph.extraSettings = {
         monClockDriftAllowed = 1;
      };

      # KVM
      flyingcircus.roles.kvm_host = {
        enable = true;
        cephRelease = clientCephRelease;
      };

      environment.sessionVariables = {
        FCQEMU_NO_TTY = "true";
      };

      # Consul
      flyingcircus.roles.consul_server.enable = true;
      services.consul.extraConfig.bootstrap_expect = lib.mkForce 1;
      services.nginx.virtualHosts."host${toString id}.fe.test.fcio.net" = {
        enableACME = lib.mkForce false;
        addSSL = true;
        sslCertificateKey = "/var/self-signed.key";
        sslCertificate = "/var/self-signed.crt";
      };
      system.activationScripts.consul_certificate = ''
        ${pkgs.openssl}/bin/openssl req -nodes -x509 -newkey rsa:4096 -keyout /var/self-signed.key -out /var/self-signed.crt -sha256 -days 365 -subj '/CN=host${toString id}'
      '';

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

      flyingcircus.enc.name = "host${toString id}";
      flyingcircus.enc.roles = [ "ceph_mon" "ceph_osd" ];
      flyingcircus.encServices = generateServices id ++ [
        {
          address = "host1.fcio.net";
          ips = [ (testlib.fcIP.sto4 1) ];
          location = "test";
          service = "ceph_mon-mon";
        }
      ];
      flyingcircus.encServiceClients = generateServiceClients id;

      environment.etc."nixos/enc.json".text = builtins.toJSON config.flyingcircus.enc;
      environment.etc."nixos/services.json".text = builtins.toJSON config.flyingcircus.encServices;
      environment.etc."nixos/service_clients.json".text = builtins.toJSON config.flyingcircus.encServiceClients;

      # Not perfect but avoids triggering the 'established' rule which can
      # lead to massive/weird Ceph instabilities.
      networking.firewall.trustedInterfaces = [ "ethsto" "ethstb" "ethsrv" "ethmgm" ];
      networking.extraHosts = ''
        ${testlib.fcIP.srv4 1} directory.fcio.net

        ${testlib.fcIP.srv6 1} host1.fcio.net
        ${testlib.fcIP.srv6 2} host2.fcio.net
        ${testlib.fcIP.srv6 3} host3.fcio.net

        ${testlib.fcIP.sto6 1} host1.sto.test.gocept.net
        ${testlib.fcIP.sto6 2} host2.sto.test.gocept.net
        ${testlib.fcIP.sto6 3} host3.sto.test.gocept.net

        ${testlib.fcIP.sto4 1} host1.sto.test.ipv4.gocept.net
        ${testlib.fcIP.sto4 2} host2.sto.test.ipv4.gocept.net
        ${testlib.fcIP.sto4 3} host3.sto.test.ipv4.gocept.net
      '';

    };
in
{
  name = "backyserver2";
  nodes = {
    host1 = makeHostConfig { id = 1; };
    # host2 = makeHostConfig { id = 2; };
    # host3 = makeHostConfig { id = 3; };
  };

  testScript = ''
    import json
    from time import sleep
    import re
    from contextlib import contextmanager

    time_waiting = 0
    start_all()

    def show(host, cmd):
        result = host.execute(cmd)[1]
        print(result)
        return result

    def revisions(host, vm):
      status = host.execute(f"backy -b /srv/backy/{vm} status --yaml | grep uuid")[1]
      r = [ l.split("uuid:")[1].strip() for l in status.splitlines() ]
      print(f"{host.name}: {vm}: found revisions:", r)
      return r

    def create_revision(host, vm):
      host.succeed(f"backy client run {vm}")
      host.wait_until_fails(f"backy client jobs {vm} | grep running")
      return revisions(host, vm)[-1]

    @contextmanager
    def mount(host, disk):
      host.succeed(f"rbd-mount {disk}")
      yield f"/mnt/rbd/{disk}"
      host.succeed(f"rbd-mount -u {disk}")

    @contextmanager
    def map(host, disk):
      dev = host.succeed(f"rbd map {disk}").strip()
      yield dev
      host.succeed(f"rbd unmap {dev}")


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
    # host2.wait_for_unit("consul")
    # host3.wait_for_unit("consul")

    time.sleep(5)
    show(host1, "journalctl -u consul")

    wait(show, host1, "consul members")
    # wait(show, host2, "consul members")
    # wait(show, host3, "consul members")

    show(host1, "journalctl -u nginx")

    # host1.wait_for_unit("nginx")
    # host2.wait_for_unit("nginx")
    # host3.wait_for_unit("nginx")

    show(host1, "ip l")
    show(host1, "iptables -L -n -v")
    show(host1, "ls -lah /etc/ceph/")
    show(host1, "cat /etc/ceph/ceph.client.admin.keyring")
    show(host1, "cat /etc/ceph/ceph.conf")
    show(host1, "cat /etc/ceph/fc-ceph.conf")

    show(host1, "lsblk")
    show(host1, "sfdisk -J /dev/vdb")

    show(host1, "ceph --version")
    # show(host2, "ceph --version")
    # show(host3, "ceph --version")


    with subtest("Initialize first mon"):
      host1.succeed("fc-ceph osd prepare-journal /dev/vdb")
      host1.execute("fc-ceph mon create --size 500m --bootstrap-cluster &> /dev/kmsg")
      host1.sleep(5)
      host1.succeed("ceph -s &> /dev/kmsg")
      host1.succeed("fc-ceph keys mon-update-single-client host1 ceph_osd,ceph_mon,kvm_host salt-for-host-1-dhkasjy9")
      host1.succeed("fc-ceph keys mon-update-single-client host2 kvm_host salt-for-host-2-dhkasjy9")

      # mgr keys rely on "fc-ceph keys" to be executes first
      host1.execute("fc-ceph mgr create --size 500m > /dev/kmsg 2>&1")

    with subtest("Initialize OSD"):
      host1.execute("fc-ceph osd create-bluestore /dev/vdc")
      host1.succeed("ceph osd crush move host1 root=default")

    with subtest("Create pools"):
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

    print("Time spent waiting", time_waiting)

    with subtest("Create image"):
      host1.succeed("rbd create --size 100 rbd.ssd/vm0.root")
      with map(host1, "rbd.ssd/vm0.root") as dev:
        host1.succeed(f"parted -s {dev} -- mklabel gpt")
        host1.succeed(f"parted -s {dev} -- mkpart primary 1MiB 100%")
        host1.succeed(f"partprobe {dev}")
        host1.succeed(f"mkfs.ext4 {dev}p1")

      with mount(host1, "rbd.ssd/vm0.root") as path:
        host1.succeed(f"echo meow > {path}/test")

    with subtest("Configure backy"):
      host1.succeed("mkdir -p /directory_response/list_virtual_machines")
      host1.succeed('echo \'[{"name":"vm0","parameters":{"backy_server":"host1","rbd_pool":"rbd.ssd"}}]\' \
                    > /directory_response/list_virtual_machines/test')
      host1.succeed("mkdir /srv/backy")
      # host2.succeed("mkdir /srv/backy")
      # host3.succeed("mkdir /srv/backy")

      host1.systemctl("start backy")
      # host2.systemctl("start backy")
      # host3.systemctl("start backy")
      host1.wait_for_unit("backy")
      # host2.wait_for_unit("backy")
      # host3.wait_for_unit("backy")
      sleep(2)

    with subtest("Create revisions"):
      show(host1, "cat /etc/backy.conf")
      assert "jobs=1" in host1.succeed("backy client check 2>&1 | cat")

      rev = create_revision(host1, "vm0")
      show(host1, "backy client jobs")
      show(host1, "backy -b /srv/backy/vm0 status")
      show(host1, "cat /var/log/backy.log")
      show(host1, "cat /srv/backy/vm0/backy.log")

      with mount(host1, "rbd.ssd/vm0.root") as path:
        host1.succeed(f"echo meow2 > {path}/test")
      rev2 = create_revision(host1, "vm0")

    with subtest("restore-single-files"):
      host1.succeed("touch rsf-in")
      host1.succeed(f"tail -f rsf-in | restore-single-files vm0 {rev} > rsf-out &")
      host1.wait_until_succeeds("grep 'Image data ready in' rsf-out")

      assert "meow" == host1.succeed("cat /mnt/restore/vm0/test").strip()

      host1.succeed("ps -e | grep restore-single-")

      host1.succeed("echo >> rsf-in")
      sleep(3)

      host1.fail("mount | grep backy")
      host1.fail("ps -e | grep restore-single-")

    with subtest("restore"):
      host1.succeed("rbd create --size 100 rbd.ssd/vm0-restore.root")

      with map(host1, "rbd.ssd/vm0-restore.root") as dev_restore:
        assert "backend='rust'" in host1.succeed(f"backy -b /srv/backy/vm0 restore -r {rev} {dev_restore} 2>&1 | cat")
      with mount(host1, "rbd.ssd/vm0-restore.root") as path:
        assert "meow" == host1.succeed(f"cat {path}/test").strip()

      with map(host1, "rbd.ssd/vm0-restore.root") as dev_restore, map(host1, "rbd.ssd/vm0.root") as dev:
        assert "backend='python'" in host1.succeed(f"BACKY_EXTRACT=\"\" backy -b /srv/backy/vm0 restore {dev_restore} 2>&1 | cat")
        host1.succeed(f"diff {dev} {dev_restore}")

      with map(host1, "rbd.ssd/vm0-restore.root") as dev_restore:
        assert "restore-stdout" in host1.succeed(f"backy -vb /srv/backy/vm0 restore -r {rev2} --backend python - 2>&1 > {dev_restore} | cat")
      with mount(host1, "rbd.ssd/vm0-restore.root") as path:
        assert "meow2" == host1.succeed(f"cat {path}/test").strip()

      with map(host1, "rbd.ssd/vm0-restore.root") as dev_restore, map(host1, "rbd.ssd/vm0.root") as dev:
        assert "backy-extract/finished" in host1.succeed(f"backy -b /srv/backy/vm0 restore --backend rust - 2>&1 > {dev_restore} | cat")
        host1.succeed(f"diff {dev} {dev_restore}")

  '';
})
