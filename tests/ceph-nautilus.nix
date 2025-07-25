import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    getIPForVLAN = vlan: id: "192.168.${toString vlan}.${toString (5 + id)}";

    makeCephHostConfig =
      {
        id,
        diskSizes ? [
          4000
          4000
        ],
        monOnly ? false,
      }:
      { config, lib, ... }:
      {
        virtualisation.memorySize = 4000;
        virtualisation.cores = 2;
        virtualisation.vlans =
          with config.flyingcircus.static.vlanIds;
          [
            srv
            sto
          ]
          ++ (if (!monOnly) then [ stb ] else [ ]);
        virtualisation.emptyDiskImages = diskSizes;
        imports = [
          ../nixos
          ../nixos/roles
        ];

        flyingcircus.infrastructure.fullDiskEncryption.enable = true;
        flyingcircus.static.mtus.sto = 1500;
        flyingcircus.static.mtus.stb = 1500;

        flyingcircus.encServices = [
          {
            address = "host1.fcio.net";
            ips = [ (getIPForVLAN 4 1) ];
            location = "test";
            service = "ceph_mon-mon";
          }
          {
            address = "host1.fcio.net";
            ips = [ (getIPForVLAN 3 1) ];
            location = "test";
            service = "ceph_rgw-server";
          }
          {
            address = "host2.fcio.net";
            ips = [ (getIPForVLAN 4 2) ];
            location = "test";
            service = "ceph_mon-mon";
          }
          {
            address = "host2.fcio.net";
            ips = [ (getIPForVLAN 3 2) ];
            location = "test";
            service = "ceph_rgw-server";
          }
          {
            address = "host3.fcio.net";
            ips = [ (getIPForVLAN 4 3) ];
            location = "test";
            service = "ceph_mon-mon";
          }
          {
            address = "host4.fcio.net";
            ips = [ (getIPForVLAN 4 4) ];
            location = "test";
            service = "ceph_mon-mon";
          }
        ];

        flyingcircus.services.ceph.extraSettings = {
          "mon clock drift allowed" = 10;
          # Since luminous, pool creation fails if it causes the number of PGs to
          # exceed "mon max pg per osd". For the NixOS test that limit needs to be
          # raised, but for dev and prod the default should still be fine.
          # In real-world clusters, better make sure to choose the correct number of
          # PGs per pool instead of overriding this setting.
          "mon max pg per osd" = 500;

          "debug monc" = 4;
        };

        # adjust pool mapping for check_snapshot_restore_fill check
        flyingcircus.services.ceph.server.crushroot_to_rbdpool_mapping = {
          default = [ "rbd" ];
        };

        # We need this in the enc files as well so that timer jobs can update
        # the keys etc.
        environment.etc."nixos/services.json".text = builtins.toJSON config.flyingcircus.encServices;

        flyingcircus.roles.ceph_osd = {
          enable = !monOnly;
          cephRelease = "nautilus";
        };
        flyingcircus.roles.ceph_mon = {
          enable = true;
          cephRelease = "nautilus";
        };
        flyingcircus.roles.ceph_rgw = {
          enable = !monOnly;
          cephRelease = "nautilus";
        };

        flyingcircus.static.ceph.fsids.test.test = "d118a9a4-8be5-4703-84c1-87eada2e6b60";

        # :( Work-around the split between qemu-built systems and regular systems.
        virtualisation.fileSystems."/mnt/keys" =
          config.flyingcircus.infrastructure.fullDiskEncryption.fsOptions;

        environment.etc."nixos/enc.json".text = builtins.toJSON {
          name = "host${toString id}";
          roles = [
            "ceph_mon"
            "ceph_osd"
            "ceph_rgw"
          ];
          parameters = {
            directory_password = "password-for-fake-directory";
            directory_url = "http://directory.fcio.net";
            directory_ring = 0;
            location = "test";
            resource_group = "services";
            secret_salt = "salt-for-host${toString id}-dhkasjy9";
            secrets = {
              "ceph/admin_key" = "AQBFJa9hAAAAABAAtdggM3mhVBAEYw3+Loehqw==";
            };
          };
        };

        networking.extraHosts = ''
          ${getIPForVLAN 4 1} host1.sto.test.ipv4.gocept.net
          ${getIPForVLAN 4 2} host2.sto.test.ipv4.gocept.net
          ${getIPForVLAN 4 3} host3.sto.test.ipv4.gocept.net
          ${getIPForVLAN 4 4} host4.sto.test.ipv4.gocept.net
          ${getIPForVLAN 3 6} directory.fcio.net
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
            gateways = { };
          };
          interfaces.sto = {
            mac = "52:54:00:12:04:0${toString id}";
            bridged = false;
            networks = {
              "192.168.4.0/24" = [ (getIPForVLAN 4 id) ];
            };
            gateways = { };
          };
          interfaces.stb = {
            mac = "52:54:00:12:08:0${toString id}";
            bridged = false;
            networks = {
              "192.168.8.0/24" = [ (getIPForVLAN 8 id) ];
            };
            gateways = { };
          };
        };
      };
  in
  {
    name = "ceph";
    nodes = {
      host1 = makeCephHostConfig {
        id = 1;
        diskSizes = [
          4000
          4000
          4000
          1100
        ];
      };
      host2 = makeCephHostConfig { id = 2; };
      host3 = makeCephHostConfig { id = 3; };
      # not utilised in the test, we only want to see the config eval succeed
      host4 = makeCephHostConfig {
        id = 4;
        monOnly = true;
      };

      node =
        { config, pkgs, ... }:
        {
          imports = [
            ../nixos
            ../nixos/roles
          ];
          virtualisation.vlans = with config.flyingcircus.static.vlanIds; [
            fe
            srv
          ];
          environment.systemPackages = [ pkgs.awscli ];
          networking.extraHosts = ''
            ${getIPForVLAN 3 1} s3.host1.fcio.net
            ${getIPForVLAN 2 7} objects.test.test.fcio.net
            ::1 s3.node.fcio.net
          '';
          flyingcircus.enc.parameters = {
            location = "test";
            resource_group = "test";
            interfaces.fe = {
              mac = "52:54:00:12:02:0${toString 5}";
              bridged = false;
              networks = {
                "192.168.2.0/24" = [ (getIPForVLAN 2 5) ];
              };
              gateways = { };
            };
            interfaces.srv = {
              mac = "52:54:00:12:03:0${toString 5}";
              bridged = false;
              networks = {
                "192.168.3.0/24" = [ (getIPForVLAN 3 5) ];
              };
              gateways = { };
            };
          };

          flyingcircus.services.haproxy = {
            enable = true;
            enableStructuredConfig = true;
            frontend = {
              http-in = {
                binds = [ "[::1]:80" ];
                default_backend = "s3";
              };
            };
            backend.s3.servers = [
              "s3-host1 s3.host1.fcio.net:7480 check inter 10s rise 2 fall 1 maxconn 1000"
            ];
          };
        };

      node_directory =
        { config, pkgs, ... }:
        {
          flyingcircus.enc.parameters = {
            location = "test";
            resource_group = "test";
            interfaces.srv = {
              mac = "52:54:00:12:03:0${toString 6}";
              bridged = false;
              networks = {
                "192.168.3.0/24" = [ (getIPForVLAN 3 6) ];
              };
              gateways = { };
            };
          };
          imports = [
            ../nixos
            ../nixos/roles
          ];
          virtualisation.vlans = with config.flyingcircus.static.vlanIds; [
            srv
          ];
          networking.firewall.allowedTCPPorts = [ 80 ];
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
        };

      rgwproxy =
        { config, lib, ... }:
        {
          imports = [
            ../nixos
            ../nixos/roles
          ];

          virtualisation.vlans = with config.flyingcircus.static.vlanIds; [
            fe
            srv
          ];
          flyingcircus.roles.rgw-location-proxy.enable = true;
          flyingcircus.enc.parameters = {
            location = "test";
            resource_group = "test";
            interfaces.fe = {
              mac = "52:54:00:12:02:0${toString 7}";
              bridged = false;
              networks = {
                "192.168.2.0/24" = [ (getIPForVLAN 2 7) ];
              };
              gateways = { };
            };
            interfaces.srv = {
              mac = "52:54:00:12:03:0${toString 7}";
              bridged = false;
              networks = {
                "192.168.3.0/24" = [ (getIPForVLAN 3 7) ];
              };
              gateways = { };
            };
          };
          flyingcircus.encServices = [
            {
              address = "host1.fcio.net";
              ips = [ (getIPForVLAN 3 1) ];
              location = "test";
              service = "ceph_rgw-server";
            }
            {
              address = "host2.fcio.net";
              ips = [ (getIPForVLAN 3 2) ];
              location = "test";
              service = "ceph_rgw-server";
            }
          ];
          services.nginx.virtualHosts."objects.test.test.fcio.net".forceSSL = lib.mkForce false;
        };

    };

    testScript =
      { nodes, ... }:
      let
        check_key_file_cmd = testlib.sensuCheckCmd nodes.host1 "keystickMounted";
      in
      ''
        import datetime
        import time
        import json

        time_waiting = 0
        TEST_HOSTS = (host1, host2, host3)
        for h in TEST_HOSTS:
          h.start()

        def show(host, cmd):
          result = host.execute(cmd)[1]
          print(result)
          return result

        def retry_attempts(host, cmd: str, tries: int=3):
          """sometimes the assert_clean_cluster does not suffice, as the cluster temporarily acts up again.
          Hacky workaround, the goal is to get rid of this again once re-architecting the test suite.
          """
          result = host.execute(cmd)
          while result[0] and tries > 0:
            tries -= 1
            time.sleep(1)
            result = host.execute(cmd)
          return result[1]

        def assert_clean_cluster(host, mons, osds, mgrs, min_pgs):
          # `osds` can be either of the form `(num_up_osds, num_in_osds)` or a single
          # integer specifying both up and in osds

          try:
            (num_up_osds, num_in_osds) = osds
          except TypeError:
            num_up_osds = osds
            num_in_osds = osds

          global time_waiting
          print(f"Waiting for clean cluster: mons={mons} osds={osds} mgrs={mgrs} pgs={min_pgs}")
          start = time.time()
          # Allow HEALTH_WARN as we do not correctly cover clock skew
          # currently
          tries = 1
          while True:
            # json status is too verbose, but still show the human-readable status
            show(host, 'ceph -s')
            show(host, 'ceph health detail | tail')
            status = json.loads(host.execute('ceph -f json-pretty -s')[1])

            try:
              t.assertIn(status["health"]["status"], ['HEALTH_OK', 'HEALTH_WARN'])
              t.assertEqual(int(status["monmap"]["num_mons"]), mons)
              osdmap_stat = status["osdmap"]["osdmap"]
              t.assertEqual(osdmap_stat["num_up_osds"], num_up_osds)
              t.assertEqual(osdmap_stat["num_in_osds"], num_in_osds)
              pgstate0 = status["pgmap"]["pgs_by_state"][0]
              t.assertGreaterEqual(pgstate0["count"], min_pgs)
              t.assertEqual(pgstate0["state_name"], "active+clean")
              t.assertTrue(status["mgrmap"]["available"])
              t.assertEqual(len(status["mgrmap"]["standbys"]), mgrs-1)
              break
            except AssertionError as e:
              if time.time() - start < 120:
                time_waiting += tries*2
                time.sleep(tries*2)
              else:
                 raise

        def wait_for_cluster_status(host, wanted_status: str):
          global time_waiting
          print("Waiting for cluster status", wanted_status, "...")
          start = time.time()
          tries = 1
          while True:
            status = json.loads(host.execute('ceph -f json-pretty -s')[1])
            # json status is too verbose, but still show the human-readable status
            show(host, 'ceph -s')
            show(host, 'ceph health detail | tail')

            for check in status["health"]["checks"].keys():
              if check == wanted_status:
                return

            if time.time() - start < 60:
              time_waiting += 5
              time.sleep(5)
            else:
              raise

        def stop_failing_service(host, servicename):
          # we cannot just wait for multi-user target, as it depends on the failing services
          print(f"Waiting for {serv}…")
          h.wait_until_succeeds(
            f'systemctl show --property=ActiveState {serv}.service | tee /dev/stderr | egrep "(ActiveState=active|ActiveState=activating|ActiveState=failed)"'
          )
          h.succeed(f"systemctl stop {serv}.service")

        # services are uninitialised, stop their unsuccessful starting attempts
        for h in TEST_HOSTS:
          for serv in ("fc-ceph-rgw", "fc-ceph-mon", "fc-ceph-mgr"):
            stop_failing_service(h, serv)

          # TODO: This is a workaround for PL-133673, fc-agent interactive logs shall **not** go to the
          # journal of `backdoor.service` only.
          h.execute("unset JOURNAL_STREAM")

        show(host1, 'ip l')
        show(host1, 'cat /etc/fstab')
        show(host1, 'cat /proc/cpuinfo')
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

        node_directory.start()

        with subtest("Initialize keystore on host 1"):
          # check succeeds as "not needed" as long as /mnt/keys does not exist
          host1.succeed("${check_key_file_cmd} > /dev/stderr")
          host1.succeed("fc-luks keystore create /dev/vde > /dev/stderr")
          show(host1, "lsblk")
          host1.succeed("${check_key_file_cmd} > /dev/stderr")


        with subtest("Initialize first mon"):
          host1.succeed('fc-ceph osd prepare-journal /dev/vdb > /dev/stderr')
          host1.succeed('echo -e "adminphrase\ny\n" | setsid -w fc-ceph mon create --encrypt --size 500m --bootstrap-cluster > /dev/stderr')
          show(host1, "ls -l /dev/disk/by-label")
          show(host1, 'lsblk')
          show(host1, 'journalctl -u fc-ceph-mon')
          host1.sleep(10)
          show(host1, 'cat /var/log/ceph/*mon*')
          show(host1, 'ps aux | grep ceph')

          host1.succeed('ceph -s > /dev/stderr')

          host1.succeed('fc-ceph keys mon-update-single-client host1 ceph_osd,ceph_mon,ceph_rgw salt-for-host1-dhkasjy9')
          host1.succeed('fc-ceph keys mon-update-single-client host2 ceph_osd,ceph_mon salt-for-host2-dhkasjy9')
          host1.succeed('fc-ceph keys mon-update-single-client host3 ceph_osd,ceph_mon salt-for-host3-dhkasjy9')

          # fix default warnings by enabling new backwards-incompatible client auth behaviour
          host1.succeed('ceph config set mon auth_allow_insecure_global_id_reclaim false > /dev/stderr')
          host1.succeed('ceph mon enable-msgr2 > /dev/stderr')

          show(host1, 'ceph auth list')

          show(host1, 'ceph mon dump')

          # mgr keys rely on 'fc-ceph keys' to be executed first
          host1.execute('echo -e "adminphrase\n" | setsid -w fc-ceph mgr create --encrypt --size 500m > /dev/stderr')
          show(host1, 'journalctl -u fc-ceph-mgr')
          show(host1, 'ceph mgr module ls')

          # rbd pool is not created by default anymore
          host1.succeed('ceph osd pool create rbd 64')
          show(host1, 'ceph osd lspools')

        with subtest("Initialize first OSD (bluestore)"):
          host1.execute('systemctl status fc-ceph-osd@0.service > /dev/stderr')
          host1.execute('echo -e "adminphrase\n" | setsid -w fc-ceph osd create-bluestore --encrypt /dev/vdc > /dev/stderr')
          host1.execute('systemctl status fc-ceph-osd@0.service > /dev/stderr')

        with subtest("Initialize second MON and OSD (bluestore, internal WAL)"):
          host2.succeed('fc-ceph osd prepare-journal /dev/vdb')
          host2.succeed('fc-ceph mon create --no-encrypt --size 500m > /dev/stderr')
          host2.execute('fc-ceph mgr create --no-encrypt --size 500m > /dev/stderr')
          # cover explicit specification of internal and external journals
          host2.succeed('fc-ceph osd create-bluestore --no-encrypt --wal=internal /dev/vdc > /dev/stderr')

        with subtest("Initialize third MON and OSD (bluestore, external WAL)"):
          host3.succeed('fc-ceph osd prepare-journal /dev/vdb')
          host3.succeed('fc-ceph mon create --no-encrypt --size 500m')
          host3.execute('fc-ceph mgr create --no-encrypt --size 500m > /dev/stderr')
          # cover explicit specification of internal and external journals
          host3.succeed('fc-ceph osd create-bluestore --no-encrypt --wal=external /dev/vdc > /dev/stderr')

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

        with subtest("S3 works"):
          import configparser

          user_data = json.loads(host1.succeed("radosgw-admin user info --uid=user"))
          t.assertTrue(user_data['keys'])
          access_key, secret_key = user_data['keys'][0]['access_key'], user_data['keys'][0]['secret_key']
          host4.succeed("mkdir -p /root/.aws")

          aws_cfg = configparser.ConfigParser()
          endpoints = {
            "default": 'http://s3.host1.fcio.net:7480',
            "port_80": 'http://objects.test.test.fcio.net',
            "customer_gw": 'http://s3.node.fcio.net',
          }

          for profile, url in endpoints.items():
            aws_cfg.add_section(profile)
            aws_cfg.set(profile, 'endpoint_url', url)
            aws_cfg.set(profile, 'aws_access_key_id', access_key)
            aws_cfg.set(profile, 'aws_secret_access_key', secret_key)

          with open("awscfg", "w") as f:
              aws_cfg.write(f)

          node.copy_from_host("awscfg", "/root/.aws/credentials")

          node.wait_until_succeeds("curl -f http://s3.host1.fcio.net:7480")
          node.wait_until_succeeds("aws s3 mb s3://test/")
          node.succeed("dd if=/dev/urandom of=testdata bs=1k count=2")
          hash_original = node.succeed("nix-hash testdata")
          rgwproxy.start()
          node.succeed("aws s3 cp testdata s3://test/testdata")

          # For the healthcheck of haproxy
          node.succeed("aws s3 mb s3://rgw-monitoring")
          node.succeed("touch foo && aws s3 cp foo s3://rgw-monitoring/probe")
          node.succeed("aws s3api put-object-acl --bucket rgw-monitoring --acl public-read --key probe")
          # HAProxy is still giving a 503 because of the failing healthcheck, so let's wait.
          node.wait_until_succeeds("curl -f http://objects.test.test.fcio.net")

          for profile in endpoints.keys():
            node.succeed(f"aws --profile {profile} s3 cp s3://test/testdata download_{profile}")
            hash_download = node.succeed(f"nix-hash download_{profile}")
            t.assertEqual(hash_original, hash_download)

        with subtest("S3 presigned URLs (PL-130368)"):
          for profile, url in endpoints.items():
            presigned_url = node.succeed(f"aws --profile {profile} s3 presign s3://test/testdata").strip()
            t.assertIn(url, presigned_url)
            node.succeed(f"curl '{presigned_url}' -o output_from_presigned_{profile}")
            hash_presigned_download = node.succeed(f"nix-hash output_from_presigned_{profile}")

            t.assertEqual(hash_original, hash_presigned_download)

        with subtest("Traffic accounting"):
          # Logs exist
          host1.succeed("radosgw-admin log list | jq '.[]' -r | sort | grep rgw-monitoring")
          log_entry = host1.succeed("radosgw-admin log list | jq '.[]' -r | sort | grep test").rstrip()

          # We do get reasonable data out of it
          logs = json.loads(host1.succeed(f"radosgw-admin log show --object={log_entry}"))
          t.assertLess(0, len(logs.get("log_entries", [])))
          t.assertLess(0, sum(ent["bytes_sent"] for ent in logs["log_entries"]))
          t.assertLess(0, sum(ent["bytes_received"] for ent in logs["log_entries"]))

          # We can run accounting over it
          host1.succeed("systemctl start fc-ceph-account-s3-traffic")
          host1.succeed("test -f /var/lib/fc-ceph-s3-accounting/s3-accounting-state")

          accounting_data = json.loads(host1.succeed("cat /var/lib/fc-ceph-s3-accounting/s3-accounting-state"))
          t.assertIn("last_processed_datetime", accounting_data)
          t.assertIn("last_gced_day", accounting_data)

          # GC works
          accounting_data["last_gced_day"] = (datetime.date.today() - datetime.timedelta(days=5)).isoformat()
          host1.succeed(f"echo '{json.dumps(accounting_data)}' > /var/lib/fc-ceph-s3-accounting/s3-accounting-state")
          host1.succeed("systemctl start fc-ceph-gc-s3-traffic-data")
          accounting_data = json.loads(host1.succeed("cat /var/lib/fc-ceph-s3-accounting/s3-accounting-state"))
          t.assertEqual(accounting_data["last_gced_day"], (datetime.date.today() - datetime.timedelta(days=2)).isoformat())

        with subtest("Destroy and re-create first mon"):
          host1.succeed('fc-ceph mon destroy')
          host1.succeed('fc-ceph mgr destroy')
          show(host1, 'rm /var/log/ceph/*mon*')
          show(host1, 'lsblk')

          assert_clean_cluster(host2, 2, 3, 2, 448)

          host1.succeed('echo -e "adminphrase\n" | setsid -w fc-ceph mon create --size 500m > /dev/stderr')
          host1.execute('echo -e "adminphrase\n" | setsid -w fc-ceph mgr create --size 500m > /dev/stderr')
          host1.sleep(5)
          show(host1, 'tail -n 500 /var/log/ceph/*mon*')
          show(host1, 'tail -n 500 /var/log/ceph/*mgr*')

          assert_clean_cluster(host2, 3, 3, 3, 448)

        with subtest("Reactivate all OSDs on host1"):
          host1.succeed('fc-ceph osd reactivate all')
          assert_clean_cluster(host2, 3, 3, 3, 448)

        with subtest("Test strict safety check of destroy and rebuild"):
          host1.fail("fc-ceph osd destroy --strict-safety-check all > /dev/stderr")
          host1.fail('fc-ceph osd rebuild --strict-safety-check all> /dev/stderr')

        with subtest("Initialize extra OSD to enable safe rebuilding (bluestore)"):
          host1.execute('fc-ceph osd create-bluestore --no-encrypt /dev/vdd > /dev/stderr')
          assert_clean_cluster(host2, 3, 4, 3, 448)

        with subtest("Rebuild the 2nd OSD on host 1 from bluestore to bluestore and disable encryption without redundancy loss"):
          # set OSDs out and wait for cluster to rebalance
          host1.execute('ceph osd out 3')
          host1.sleep(5)
          assert_clean_cluster(host2, 3, (4, 3), 3, 448)
          # then rebuild
          host1.succeed('echo -e "adminphrase\n" | setsid -w fc-ceph osd rebuild --no-encrypt --strict-safety-check 3 > /dev/stderr')
          # and set the osds in again
          host1.execute('ceph osd in $(ceph osd ls-tree host1)')
          show(host1, "lsblk")
          show(host1, "vgs")
          host1.sleep(5)
          assert_clean_cluster(host2, 3, 4, 3, 448)

        with subtest("Rebuild all OSDs on host 1 and ensure encryption is enabled"):
          host1.succeed('echo -e "adminphrase\n" | setsid -w fc-ceph osd rebuild --encrypt --no-safety-check all > /dev/stderr')
          assert_clean_cluster(host2, 3, 4, 3, 448)

        with subtest("Destroy the 2nd OSD on host 1 without redundancy loss"):
          # set OSDs out and wait for cluster to rebalance
          host1.execute('ceph osd out 3')
          host1.sleep(5)
          assert_clean_cluster(host2, 3, (4, 3), 3, 448)
          # then destroy
          host1.succeed('fc-ceph osd destroy --strict-safety-check 3 > /dev/stderr')
          show(host1, "lsblk")
          show(host1, "vgs")
          assert_clean_cluster(host2, 3, 3, 3, 448)

        # from now on always default to allowing some reduced redundancy to save time

        with subtest("Rebuild all OSDs on host 2"):
          retry_attempts(host2, 'fc-ceph osd rebuild all > /dev/stderr')
          show(host1, "lsblk")
          show(host1, "vgs")
          assert_clean_cluster(host3, 3, 3, 3, 448)

        with subtest("Deactivate and activate single OSD on host 1"):
          host1.fail('fc-ceph osd deactivate --strict-safety-check 0')
          host1.succeed('fc-ceph osd deactivate 0')
          host1.succeed('fc-ceph osd activate 0')
          status = show(host2, 'ceph -s')
          assert_clean_cluster(host2, 3, 3, 3, 448)

        with subtest("Test destroy safety check and its override, destroy, recreate, recover OSDs"):
          host2.succeed('fc-ceph osd destroy all > /dev/stderr')
          wait_for_cluster_status(host3, "PG_DEGRADED")
          host3.fail('fc-ceph osd destroy all > /dev/stderr')
          host3.succeed('fc-ceph osd destroy --no-safety-check all > /dev/stderr')
          # now the cluster should block I/O due to being on only 1/3 redundancy
          wait_for_cluster_status(host3, "PG_AVAILABILITY")
          host3.succeed('ceph health | grep "Reduced data availability" > /dev/stderr')
          # re-provision the 2 OSDs and allow the cluster to recover
          host2.succeed('fc-ceph osd create-bluestore --no-encrypt --wal=internal /dev/vdc > /dev/stderr')
          host3.succeed('fc-ceph osd create-bluestore --no-encrypt --wal=external /dev/vdc > /dev/stderr')
          assert_clean_cluster(host2, 3, 3, 3, 448)

        # Maintenance integration
        with subtest("Check maintenance integration"):

          host1.execute("rm /var/log/fc-agent.log")
          host1.execute('fc-maintenance -v request script "test" "ceph -s"')
          result = host1.execute("cat /var/log/fc-agent.log")[1]
          print("="*80)
          print(result)

          host1.execute("rm /var/log/fc-agent.log")
          host1.execute('fc-maintenance -v run --no-online --run-all-now 2>&1')
          result = host1.execute("cat /var/log/fc-agent.log")[1]
          print("="*80)
          print(result)

          assert "fc-ceph maintenance enter" in result, "maintenance enter not seen"
          assert "systemctl stop fc-ceph-rgw" in result, "fc-ceph-rgw not stopped"

          assert "1 OSDs or CRUSH {nodes, device-classes} have {NOUP,NODOWN,NOIN,NOOUT} flags set" in result, "flags not set"
          assert "osds down" in result, "osds not down"

          assert "systemctl start fc-ceph-rgw" in result, "rgw not started"
          assert "fc-ceph maintenance leave" in result, "maintenance not left"

          assert_clean_cluster(host2, 3, 3, 3, 448)

        # TODO: include test for rbd map rbdnamer udev rule functionality, after having rebased onto PL-130691

        # commented out because this test sometimes succeeds, but often just hangs
        #with subtest("Integration test for check_snapshot_restore_fill"):
        #  check_command = "${nodes.host1.flyingcircus.services.sensu-client.checks.ceph_snapshot_restore_fill.command}"
        #  print("Executing check command", check_command)
        #  snapfillcheck = host1.succeed('sudo -u sensuclient ' + check_command + ' > /dev/stderr')
        #  print(snapfillcheck)

        #  # calculation of image size: The empty image itself accounts for almost nothing,
        #  # but after generating a snapshot it's accounted size is the provisioned size of
        #  # the image.
        #  # Thus, we need to create an image of the size that can exceed the threshold alone.
        #  host1.succeed("rbd create rbd/snapfilltest -s 5324M > /dev/stderr")
        #  host1.succeed("rbd snap create rbd/snapfilltest@firstsnap > /dev/stderr")

        #  host1.sleep(1)
        #  print("Executing check command", check_command)
        #  snapfillcheck = host1.execute('sudo -u sensuclient ' + check_command + ' >&2')
        #  print(snapfillcheck[1])
        #  assert snapfillcheck[0] == 2

        print("Time spent waiting", time_waiting)
      '';
  }
)
