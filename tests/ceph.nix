import ./make-test-python.nix ({ ... }:
let
  getIPForVLAN = vlan: id: "192.168.${toString vlan}.${toString (5 + id)}";

  makeCephHostConfig = { id }:
    { config, ... }:
    {

      virtualisation.memorySize = 3000;
      virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ srv sto stb ];
      virtualisation.emptyDiskImages = [ 4000 4000 ];
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

      flyingcircus.services.ceph.extraConfig = ''
            mon clock drift allowed = 1
      '';

      # We need this in the enc files as well so that timer jobs can update
      # the keys etc.
      environment.etc."nixos/services.json".text = builtins.toJSON config.flyingcircus.encServices;

      flyingcircus.roles.ceph_osd.enable = true;
      flyingcircus.roles.ceph_mon.enable = true;
      flyingcircus.roles.ceph_rgw.enable = true;

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
    host1 = makeCephHostConfig { id = 1; };
    host2 = makeCephHostConfig { id = 2; };
    host3 = makeCephHostConfig { id = 3; };
  };

  testScript = ''
    time_waiting = 0
    start_all()

    import time
    def show(host, cmd):
        result = host.execute(cmd)[1]
        print(result)
        return result

    def assert_clean_cluster(host, mons, osds, pgs):
      global time_waiting
      print("Waiting for clean cluster ...")
      start = time.time()
      # Allow HEALTH_WARN as we do not correctly cover clock skew
      # currently
      tries = 1
      while True:
        status = show(host1, 'ceph -s')
        show(host, 'ceph health detail | tail')

        try:
          assert 'HEALTH_OK' in status or 'HEALTH_WARN' in status
          assert f'{mons} mons at' in status
          assert f'{osds} osds: {osds} up, {osds} in' in status
          assert f'{pgs} active+clean' in status
          break
        except AssertionError:
          if time.time() - start < 60:
            time_waiting += tries*2
            time.sleep(tries*2)
          else:
             raise

    show(host1, 'ip l')
    show(host1, 'iptables -L -n -v')
    show(host1, 'ls -lah /etc/ceph/')
    show(host1, 'cat /etc/ceph/ceph.client.osd.keyring')
    show(host1, 'cat /etc/ceph/ceph.conf')

    show(host1, 'lsblk')
    show(host1, 'sfdisk -J /dev/vdb')

    host1.execute("systemctl stop fc-ceph-rgw")
    host2.execute("systemctl stop fc-ceph-rgw")
    host3.execute("systemctl stop fc-ceph-rgw")

    with subtest("Initialize first mon"):
      host1.succeed('fc-ceph osd prepare-journal /dev/vdb')
      host1.execute('fc-ceph mon create --size 500m --bootstrap-cluster &> /dev/kmsg')
      show(host1, 'lsblk')
      show(host1, 'journalctl -u fc-ceph-mon')
      host1.sleep(10)
      show(host1, 'cat /var/log/ceph/*mon*')

      host1.succeed('ceph -s &> /dev/kmsg')

      host1.succeed('fc-ceph keys mon-update-single-client host1 ceph_osd,ceph_mon,ceph_rgw salt-for-host-1-dhkasjy9')
      host1.succeed('fc-ceph keys mon-update-single-client host2 ceph_osd,ceph_mon salt-for-host-2-dhkasjy9')
      host1.succeed('fc-ceph keys mon-update-single-client host3 ceph_osd,ceph_mon salt-for-host-3-dhkasjy9')

    with subtest("Initialize first OSD"):
      host1.execute('fc-ceph osd create --journal-size=500m /dev/vdc')

    with subtest("Initialize second MON and OSD"):
      host2.succeed('fc-ceph osd prepare-journal /dev/vdb')
      host2.succeed('fc-ceph mon create --size 500m &> /dev/kmsg')
      host2.succeed('fc-ceph osd create --journal-size=500m /dev/vdc')

    with subtest("Initialize third MON and OSD"):
      host3.succeed('fc-ceph osd prepare-journal /dev/vdb')
      host3.succeed('fc-ceph mon create --size 500m')
      host3.succeed('fc-ceph osd create --journal-size=500m /dev/vdc')

    with subtest("Move OSDs to correct crush location"):
      host1.succeed('ceph osd crush move host1 root=default')
      host1.succeed('ceph osd crush move host2 root=default')
      host1.succeed('ceph osd crush move host3 root=default')
      # Let things settle for a bit, otherwise things are in weird
      # intermediate states like pgs not created, time not in sync,
      # mons not accessible, ...
      show(host1, 'ceph osd df tree')
      assert_clean_cluster(host1, 3, 3, 64)
      assert_clean_cluster(host2, 3, 3, 64)
      assert_clean_cluster(host3, 3, 3, 64)

    # Now that we have a working cluster, lets exercise:

    with subtest("Check RGW works"):
      host1.execute("systemctl restart fc-ceph-rgw")
      host1.wait_for_unit("fc-ceph-rgw.service")
      host1.succeed("radosgw-admin user create --uid=user --display-name=user")
      result = host1.succeed("radosgw-admin metadata list user")
      assert '"user"' in result
      # New pools = more PGs
      assert_clean_cluster(host2, 3, 3, 512)

    with subtest("Destroy and re-create first mon"):
      host1.succeed('fc-ceph mon destroy')
      show(host1, 'rm /var/log/ceph/*mon*')
      show(host1, 'lsblk')

      assert_clean_cluster(host2, 2, 3, 512)

      host1.succeed('fc-ceph mon create --size 500m &> /dev/kmsg')
      host1.sleep(5)
      show(host1, 'tail -n 500 /var/log/ceph/*mon*')

      assert_clean_cluster(host2, 3, 3, 512)

    with subtest("Reactivate all OSDs on host1"):
      host1.succeed('fc-ceph osd reactivate all')
      assert_clean_cluster(host2, 3, 3, 512)

    with subtest("Rebuild all OSDs on host 1"):
      host1.succeed('fc-ceph osd rebuild --journal-size=500m all &> /dev/kmsg')
      show(host1, "lsblk")
      show(host1, "vgs")
      assert_clean_cluster(host2, 3, 3, 512)

    with subtest("Deactivate and activate single OSD on host 1"):
      host1.succeed('fc-ceph osd deactivate 0')
      host1.succeed('fc-ceph osd activate 0')
      status = show(host2, 'ceph -s')
      assert_clean_cluster(host2, 3, 3, 512)

    with subtest("Destroy and create OSD on host1"):
      host1.succeed('fc-ceph osd destroy 0')
      host1.succeed('fc-ceph osd create --journal-size=500m /dev/vdc')
      assert_clean_cluster(host2, 3, 3, 512)

    print("Time spent waiting", time_waiting)
  '';
})
