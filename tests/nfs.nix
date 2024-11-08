import ./make-test-python.nix ({ pkgs, ... }:

let
  user = {
    isNormalUser = true;
    uid = 1001;
    name = "test";
  };

  encServices = [{
    address = "server.gocept.net";  # gocept.net due to PL-133063
    service = "nfs_rg_share-server";
  }];

  encServiceClients = [
    {
      node = "client1.gocept.net";  # gocept.net due to PL-133063
      service = "nfs_rg_share-server";
    }
    {
      node = "client2";
      service = "nfs_rg_share-server";
    }
  ];

  sdir = "/srv/nfs/shared";
  cdir = "/mnt/nfs/shared";

  php_blocking_script = pkgs.writeTextFile {
      name = "index.php" ;
      text = ''
        <?
          $handle = fopen("${cdir}/test2", "wb");
          fwrite($handle, "asdf");
          fflush($handle);
          sleep(600000);
        ?>
  ''; };
  clientConfig = extraConfig: { lib, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      config = lib.recursiveUpdate {
        flyingcircus.roles.nfs_rg_client.enable = true;
        flyingcircus.roles.lamp.enable = true;
        flyingcircus.roles.webgateway.enable = true;

        flyingcircus.roles.lamp.vhosts = [
          { port = 8000;
            docroot = cdir;
          }
        ];

        # XXX: same as upstream test, let's see how they fix this
        networking.firewall.enable = false;
        flyingcircus.encServices = encServices;

        # The test framework overrides the fileSystems setting from the role,
        # we must add it here with a higher priority
        fileSystems = lib.mkVMOverride {
          "${cdir}" = {
            # TODO: Due to having to override this here, the normalisation of
            # the server name in the filesystem entry is not tested.
            device = "server.fcio.net:${sdir}";
            fsType = "nfs4";
            ################################################################
            # WARNING: those settings are DUPLICATED in nixos/roles/nfs.nix
            # to work around a deficiency of the test harness.
            ################################################################
            options = [
              "rw"
              "auto"
              # Retry infinitely
              "hard"
              # perform mount unit activation in background to avoid
              # blocking nixos-rebuild switches if the server isn't
              # responsive at that point in time.
              "x-systemd.automount"
              # Start over the retry process after 10 tries
              "retrans=10"
              # Start with a 3s (30 deciseconds) interval and add 3s as linear
              # backoff
              "timeo=30"
              "rsize=8192"
              "wsize=8192"
              "nfsvers=4"
            ];
          noCheck = true;
        };
      };

        users.users.u = user;
      }
      extraConfig;
    };

in {
  name = "nfs";
  nodes = {
    client1 = clientConfig {
        networking.domain = "fcio.net"; # PL-133063
    };
    client2 = clientConfig {};

    server =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        config = {
          flyingcircus.roles.nfs_rg_share.enable = true;
          flyingcircus.encServiceClients = encServiceClients;
          # XXX: same as upstream test, let's see how they fix this
          networking.firewall.enable = false;
          users.users.u = user;
          networking.domain = "fcio.net"; # PL-133063

          specialisation.withCustomFlags.configuration.flyingcircus.roles.nfs_rg_share.clientFlags = [ "rw" "sync" "no_root_squash" "no_subtree_check" ];
        };
      };
  };

  testScript = { nodes, ... }: ''
    import io
    import queue
    import re
    import time

    server.start()
    server.wait_for_unit("nfs-server")
    server.wait_for_unit("nfs-idmapd")
    server.wait_for_unit("nfs-mountd")
    client1.start()
    client2.start()

    server.succeed("chown test ${sdir}")

    # user test on server should be able to write to shared dir
    server.succeed("sudo -u test sh -c 'echo test_on_server > ${sdir}/test'")

    # share will be mounted after boot
    client1.wait_for_unit("multi-user.target")
    client2.wait_for_unit("multi-user.target")

    client1.succeed("grep test_on_server ${cdir}/test")

    client1.succeed("sudo -u test sh -c 'echo test_on_client > ${cdir}/test'")
    server.succeed("grep test_on_client ${sdir}/test")

    client1.fail("echo from_root_user > ${cdir}/test")
    server.succeed("grep test_on_client ${sdir}/test")

    # Verify proper shutdown while NFS is being used.
    # See PL-129954
    client1.wait_for_unit("httpd.service")
    client1.succeed("cd ${cdir}")

    server.copy_from_host("${php_blocking_script}", "${sdir}/index.php")

    client1.execute('curl -v http://localhost:8000/index.php >&2 &')
    time.sleep(2)
    print(client1.execute('lsof -n ${cdir}/test2')[1])
    print(client1.execute('journalctl -u httpd')[1])
    content = client1.execute('cat ${cdir}/test2')[1]
    assert content == "asdf", repr(content)

    # PL-133063
    with subtest("NFS client and server can be resolved via /etc/hosts"):
      server_hosts = server.succeed('cat /etc/hosts')
      print("server_hosts", server_hosts, sep="\n")
      client1_hosts = client1.succeed('cat /etc/hosts')
      print("client1_hosts", client1_hosts, sep="\n")
      client2_hosts = client2.succeed('cat /etc/hosts')
      print("client2_hosts", client2_hosts, sep="\n")
      exportinfo = server.succeed('cat /etc/exports')
      print("exportinfo", exportinfo, sep="\n")
      mountinfo_client1 = client1.succeed('cat /etc/fstab | grep ${cdir}')
      print("mountinfo_client1", mountinfo_client1, sep="\n")
      mountinfo_client2 = client2.succeed('cat /etc/fstab | grep ${cdir}')
      print("mountinfo_client2", mountinfo_client2, sep="\n")

      assert "client1.fcio.net client1" in server_hosts, "client1.fcio.net missing from server hosts file"
      assert "server.fcio.net" in client1_hosts, "server missing from client1 host file"
      assert "server.fcio.net" in mountinfo_client1, "NFS server domain missing from fstab"
      assert "client1.fcio.net(" in exportinfo, "client1 domain missing from exports file"

      # TODO: For machines without a domain, the mechanism does not fully work as intended:
      # `client2` only announces itself without a domain in `flyingcircus.encAddresses`
      # and thus is present only as `client2` in /etc/hosts. But for NFS mounts, its hostname is
      # appended to the local domain of each other machine locally.
      # Hence, resolving the NFS domain name is not possible via the hosts file in
      # this particular edge case, it cannot be exported to successfully, and the NFS mounting fails.

      # As a workaround this is acceptable, as all real machines share the same domain.
      # The asserts below reflect the *is* state, not the *desired* state:
      assert "client2" in server_hosts, "client2 missing from server hosts file"
      assert "client2.fcio.net(" in exportinfo, "client2 missing from exports file"
      assert "server.fcio.net" in mountinfo_client2, "NFS server domain missing from fstab"

      print(client1.execute("findmnt")[1])
      print(client2.execute("findmnt")[1])
      print(client2.execute("systemctl status mnt-nfs-shared.mount")[1])

    deadline = time.time() + 10
    def wait_for_console_text(self, regex: str) -> str:
        self.log("waiting for {} to appear on console".format(regex))
        # Buffer the console output, this is needed
        # to match multiline regexes.
        console = io.StringIO()
        while time.time() < deadline:
            try:
                console.write(self.last_lines.get(block=False))
            except queue.Empty:
                time.sleep(1)
                continue
            console.seek(0)
            matches = re.search(regex, console.read())
            if matches is not None:
                return console.getvalue()

        assert False, "Did not shut down cleanly (timeout)"

    client1.execute("poweroff", check_return=False)

    console = wait_for_console_text(client1, "reboot: Power down")

    assert "Failed unmounting" not in console, "Unmounting NFS cleanly failed, check console output"

    client1.wait_for_shutdown()

    config = server.execute('cat /etc/exports')[1]
    assert "rw,sync,root_squash,no_subtree_check" in config, "default flags not found"

    server.succeed('${nodes.server.system.build.toplevel}/specialisation/withCustomFlags/bin/switch-to-configuration test')

    config = server.execute('cat /etc/exports')[1]
    assert "rw,sync,root_squash,no_subtree_check" not in config, "default flags found but not expected"
    assert "rw,sync,no_root_squash,no_subtree_check" in config, "custom flags not found"

  '';

})
