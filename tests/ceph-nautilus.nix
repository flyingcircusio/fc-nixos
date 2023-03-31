import ./make-test-python.nix ({ ... }:
let
  getIPForVLAN = vlan: id: "192.168.${toString vlan}.${toString (5 + id)}";

  makeCephHostConfig = { id, numDisks ? 2 }:
    { config, ... }:
    {

      virtualisation.memorySize = 3000;
      virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ srv sto stb ];
      virtualisation.emptyDiskImages = builtins.genList (_: 4000) numDisks;
      imports = [ ../nixos ../nixos/roles ];

      flyingcircus.static.mtus.sto = 1500;
      flyingcircus.static.mtus.stb = 1500;

      flyingcircus.encServices = [
        {
          address = "host1.fcio.net";
          ips = [ (getIPForVLAN 4 1) ];
          location = "test";
          service = "ceph_mon-mon";
        }        {
          address = "host2.fcio.net";
          ips = [ (getIPForVLAN 4 2) ];
          location = "test";
          service = "ceph_mon-mon";
        }        {
          address = "host3.fcio.net";
          ips = [ (getIPForVLAN 4 3) ];
          location = "test";
          service = "ceph_mon-mon";
        }
      ];

      flyingcircus.services.ceph.extraSettings = {
        "mon clock drift allowed" = 1;
        # Since luminous, pool creation fails if it causes the number of PGs to
        # exceed "mon max pg per osd". For the NixOS test that limit needs to be
        # raised, but for dev and prod the default should still be fine.
        # In real-world clusters, better make sure to choose the correct number of
        # PGs per pool instead of overriding this setting.
        "mon max pg per osd" = 500;

        "debug monc" = 4;
      };

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
      flyingcircus.roles.ceph_rgw = {
        enable = true;
        cephRelease = "nautilus";
      };

      flyingcircus.static.ceph.fsids.test.test = "d118a9a4-8be5-4703-84c1-87eada2e6b60";

      environment.etc."nixos/enc.json".text = builtins.toJSON {
        name =  "host${toString id}";
        roles = [ "ceph_mon" "ceph_osd" "ceph_rgw" ];
        parameters = {
          location = "test";
          resource_group = "services";
          secret_salt = "salt-for-host-${toString id}-dhkasjy9";
          secrets = { "ceph/admin_key" = "AQBFJa9hAAAAABAAtdggM3mhVBAEYw3+Loehqw=="; };
        };
      };

      # Not perfect but avoids triggering the 'established' rule which can
      # lead to massive/weird Ceph instabilities.
      networking.firewall.trustedInterfaces = [ "ethsto" "ethstb" ];
      networking.extraHosts = ''
        ${getIPForVLAN 4 1} host1.sto.test.ipv4.gocept.net
        ${getIPForVLAN 4 2} host2.sto.test.ipv4.gocept.net
        ${getIPForVLAN 4 3} host3.sto.test.ipv4.gocept.net
      '';

      flyingcircus.enc.parameters = {
        location = "test";
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:03:0${toString id}";
          bridged = false;
          networks = {
            "192.168.3.0/24" = [ (getIPForVLAN 3 id) ];
          };
          gateways = {};
        };
        interfaces.sto = {
          mac = "52:54:00:12:04:0${toString id}";
          bridged = false;
          networks = {
            "192.168.4.0/24" = [ (getIPForVLAN 4 id) ];
          };
          gateways = {};
        };
        interfaces.stb = {
          mac = "52:54:00:12:08:0${toString id}";
          bridged = false;
          networks = {
            "192.168.8.0/24" = [ (getIPForVLAN 8 id) ];
          };
          gateways = {};
        };
      };
    };
in
{
  name = "ceph";
  nodes = {
    host1 = makeCephHostConfig { id = 1; numDisks=3; };
    host2 = makeCephHostConfig { id = 2; };
    host3 = makeCephHostConfig { id = 3; };
  };

  testScript = ''
    time_waiting = 0
    start_all()

    import time
    import json

    def show(host, cmd):
        result = host.execute(cmd)[1]
        print(result)
        return result

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

    show(host1, 'ip l')
    show(host1, 'iptables -L -n -v')
    show(host1, 'ls -lah /etc/ceph/')
    show(host1, 'cat /etc/ceph/ceph.client.admin.keyring')
    show(host1, 'cat /etc/ceph/ceph.conf')
    show(host1, 'cat /etc/ceph/fc-ceph.conf')

    show(host1, 'lsblk')
    show(host1, 'sfdisk -J /dev/vdb')

    show(host1, 'ceph --version')
    show(host2, 'ceph --version')
    show(host3, 'ceph --version')

    host1.execute("systemctl stop fc-ceph-rgw")
    host2.execute("systemctl stop fc-ceph-rgw")
    host3.execute("systemctl stop fc-ceph-rgw")

    with subtest("Initialize first mon"):
      host1.succeed('fc-ceph osd prepare-journal /dev/vdb > /dev/kmsg 2>&1')
      host1.execute('fc-ceph mon create --size 500m --bootstrap-cluster > /dev/kmsg 2>&1')
      show(host1, "ls -l /dev/disk/by-label")
      show(host1, 'lsblk')
      show(host1, 'journalctl -u fc-ceph-mon')
      host1.sleep(10)
      show(host1, 'cat /var/log/ceph/*mon*')
      show(host1, 'ps aux | grep ceph')

      host1.succeed('ceph -s > /dev/kmsg 2>&1')

      host1.succeed('fc-ceph keys mon-update-single-client host1 ceph_osd,ceph_mon,ceph_rgw salt-for-host-1-dhkasjy9')
      host1.succeed('fc-ceph keys mon-update-single-client host2 ceph_osd,ceph_mon salt-for-host-2-dhkasjy9')
      host1.succeed('fc-ceph keys mon-update-single-client host3 ceph_osd,ceph_mon salt-for-host-3-dhkasjy9')

      # fix default warnings by enabling new backwards-incompatible client auth behaviour
      host1.succeed('ceph config set mon auth_allow_insecure_global_id_reclaim false > /dev/kmsg 2>&1')
      host1.succeed('ceph mon enable-msgr2 > /dev/kmsg 2>&1')

      show(host1, 'ceph auth list')

      show(host1, 'ceph mon dump')

      # mgr keys rely on 'fc-ceph keys' to be executes first
      host1.execute('fc-ceph mgr create --size 500m > /dev/kmsg 2>&1')
      show(host1, 'journalctl -u fc-ceph-mgr')
      show(host1, 'ceph mgr module ls')

      # rbd pool is not created by default anymore
      host1.succeed('ceph osd pool create rbd 64')
      show(host1, 'ceph osd lspools')


    with subtest("Initialize first OSD (bluestore)"):
      host1.execute('fc-ceph osd create-bluestore /dev/vdc > /dev/kmsg 2>&1')

    with subtest("Initialize second MON and OSD (filestore)"):
      host2.succeed('fc-ceph osd prepare-journal /dev/vdb')
      host2.succeed('fc-ceph mon create --size 500m > /dev/kmsg 2>&1')
      host2.execute('fc-ceph mgr create --size 500m > /dev/kmsg 2>&1')
      # cover explicit specification of internal and external journals
      host2.succeed('fc-ceph osd create-filestore --journal=internal --journal-size=500m /dev/vdc > /dev/kmsg 2>&1')

    with subtest("Initialize third MON and OSD (bluestore)"):
      host3.succeed('fc-ceph osd prepare-journal /dev/vdb')
      host3.succeed('fc-ceph mon create --size 500m')
      host3.execute('fc-ceph mgr create --size 500m > /dev/kmsg 2>&1')
      # cover explicit specification of internal and external journals
      host3.succeed('fc-ceph osd create-bluestore --wal=external /dev/vdc > /dev/kmsg 2>&1')

    with subtest("Move OSDs to correct crush location"):
      host1.succeed('ceph osd crush move host1 root=default')
      host1.succeed('ceph osd crush move host2 root=default')
      host1.succeed('ceph osd crush move host3 root=default')
      # Let things settle for a bit, otherwise things are in weird
      # intermediate states like pgs not created, time not in sync,
      # mons not accessible, ...
      show(host2, 'ceph -s')

      show(host3, 'ceph -s')
      # this command may block on an unhealthy cluster with mon issues
      show(host1, 'ceph osd df tree')
      show(host1, "ps aux | grep ceph-mgr")
      assert_clean_cluster(host1, 3, 3, 3, 64)
      assert_clean_cluster(host2, 3, 3, 3, 64)
      assert_clean_cluster(host3, 3, 3, 3, 64)

    # Now that we have a working cluster, lets exercise:

    with subtest("initialise rbd pool"):
      host1.succeed('rbd pool init')

    with subtest("Check RGW works"):
      host1.execute("systemctl restart fc-ceph-rgw")
      host1.wait_for_unit("fc-ceph-rgw.service")
      host1.succeed("radosgw-admin user create --uid=user --display-name=user")
      result = host1.succeed("radosgw-admin metadata list user")
      assert '"user"' in result
      # New pools = more PGs
      show(host2, 'ceph osd lspools')
      assert_clean_cluster(host2, 3, 3, 3, 320)

    with subtest("Destroy and re-create first mon"):
      host1.succeed('fc-ceph mon destroy')
      host1.succeed('fc-ceph mgr destroy')
      show(host1, 'rm /var/log/ceph/*mon*')
      show(host1, 'lsblk')

      assert_clean_cluster(host2, 2, 3, 2, 320)

      host1.succeed('fc-ceph mon create --size 500m > /dev/kmsg 2>&1')
      host1.succeed('fc-ceph mgr create --size 500m > /dev/kmsg 2>&1')
      host1.sleep(5)
      show(host1, 'tail -n 500 /var/log/ceph/*mon*')
      show(host1, 'tail -n 500 /var/log/ceph/*mgr*')

      assert_clean_cluster(host2, 3, 3, 3, 320)

    with subtest("Reactivate all OSDs on host1"):
      host1.succeed('fc-ceph osd reactivate all')
      assert_clean_cluster(host2, 3, 3, 3, 320)

    with subtest("Test safety check of destroy and rebuild"):
      host1.fail("fc-ceph osd destroy all > /dev/kmsg 2>&1")
      host1.fail('fc-ceph osd rebuild --journal-size=500m all > /dev/kmsg 2>&1')

    with subtest("Initialize extra OSD to enable safe rebuilding (bluestore)"):
      host1.execute('fc-ceph osd create-bluestore /dev/vdd > /dev/kmsg 2>&1')
      assert_clean_cluster(host2, 3, 4, 3, 320)

    with subtest("Safely rebuild the 2nd OSD on host 1 from bluestore to bluestore"):
      # set OSDs out and wait for cluster to rebalance
      host1.execute('ceph osd out 3')
      host1.sleep(5)
      assert_clean_cluster(host2, 3, (4, 3), 3, 320)
      # then rebuild
      host1.succeed('fc-ceph osd rebuild --journal-size=500m 3 > /dev/kmsg 2>&1')
      # and set the osds in again
      host1.execute('ceph osd in $(ceph osd ls-tree host1)')
      show(host1, "lsblk")
      show(host1, "vgs")
      host1.sleep(5)
      assert_clean_cluster(host2, 3, 4, 3, 320)

    with subtest("Safely destroy the 2nd OSD on host 1"):
      # set OSDs out and wait for cluster to rebalance
      host1.execute('ceph osd out 3')
      host1.sleep(5)
      assert_clean_cluster(host2, 3, (4, 3), 3, 320)
      # then destroy
      host1.succeed('fc-ceph osd destroy 3 > /dev/kmsg 2>&1')
      show(host1, "lsblk")
      show(host1, "vgs")
      assert_clean_cluster(host2, 3, 3, 3, 320)

    # from now on always use unsafe destroy to save time

    with subtest("Rebuild all OSDs on host 2 from filestore to filestore"):
      host2.succeed('fc-ceph osd rebuild --unsafe-destroy --journal-size=500m all > /dev/kmsg 2>&1')
      show(host1, "lsblk")
      show(host1, "vgs")
      assert_clean_cluster(host3, 3, 3, 3, 320)

    with subtest("Rebuild OSDs from one type to another"):
      host3.succeed('fc-ceph osd rebuild --unsafe-destroy --journal-size=500m --target-objectstore-type=filestore all > /dev/kmsg 2>&1')
      show(host1, "lsblk")
      show(host1, "vgs")
      assert_clean_cluster(host1, 3, 3, 3, 320)
      host2.succeed('fc-ceph osd rebuild --unsafe-destroy --journal-size=500m -T bluestore all > /dev/kmsg 2>&1')
      show(host1, "lsblk")
      show(host1, "vgs")
      assert_clean_cluster(host3, 3, 3, 3, 320)

    with subtest("Deactivate and activate single OSD on host 1"):
      host1.succeed('fc-ceph osd deactivate 0')
      host1.succeed('fc-ceph osd activate 0')
      status = show(host2, 'ceph -s')
      assert_clean_cluster(host2, 3, 3, 3, 320)

    with subtest("Destroy and create OSD on host1"):
      host1.succeed('fc-ceph osd destroy --unsafe-destroy 0')
      host1.succeed('fc-ceph osd create-bluestore /dev/vdc > /dev/kmsg 2>&1')
      assert_clean_cluster(host2, 3, 3, 3, 320)

    print("Time spent waiting", time_waiting)
  '';
})
