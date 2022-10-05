import ./make-test-python.nix ({ pkgs, ... }:

let
  user = {
    isNormalUser = true;
    uid = 1001;
    name = "test";
  };

  encServices = [{
    address = "server";
    service = "nfs_rg_share-server";
  }];

  encServiceClients = [{
    node = "client";
    service = "nfs_rg_share-server";
  }];

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

in {
  name = "nfs";
  nodes = {
    client =
      { lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        config = {
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
          services.telegraf.enable = false;

          # The test framework overrides the fileSystems setting from the role,
          # we must add it here with a higher priority
          fileSystems = lib.mkVMOverride {
            "${cdir}" = {
              device = "server:${sdir}";
              fsType = "nfs4";
              options = [
                "rw"
                "soft"
                "rsize=8192"
                "wsize=8192"
                "nfsvers=4"
              ];
            noCheck = true;
          };
        };

          users.users.u = user;
        };

      };

    server =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        config = {
          flyingcircus.roles.nfs_rg_share.enable = true;
          flyingcircus.encServiceClients = encServiceClients;
          # XXX: same as upstream test, let's see how they fix this
          networking.firewall.enable = false;
          services.telegraf.enable = false;
          users.users.u = user;

        };
      };
  };

  testScript = ''
    import io
    import queue
    import re
    import time

    server.start()
    server.wait_for_unit("nfs-server")
    server.wait_for_unit("nfs-idmapd")
    server.wait_for_unit("nfs-mountd")
    client.start()

    server.succeed("chown test ${sdir}")

    # user test on server should be able to write to shared dir
    server.succeed("sudo -u test sh -c 'echo test_on_server > ${sdir}/test'")

    # share will be mounted after boot
    client.wait_for_unit("multi-user.target")

    client.succeed("grep test_on_server ${cdir}/test")

    client.succeed("sudo -u test sh -c 'echo test_on_client > ${cdir}/test'")
    server.succeed("grep test_on_client ${sdir}/test")

    client.fail("echo from_root_user > ${cdir}/test")
    server.succeed("grep test_on_client ${sdir}/test")

    # Verify proper shutdown while NFS is being used.
    # See PL-129954
    client.wait_for_unit("httpd.service")
    client.succeed("cd ${cdir}")

    server.copy_from_host("${php_blocking_script}", "${sdir}/index.php")

    client.execute('curl -v http://localhost:8000/index.php >&2 &')
    time.sleep(2)
    print(client.execute('lsof -n ${cdir}/test2')[1])
    print(client.execute('journalctl -u httpd')[1])
    content = client.execute('cat ${cdir}/test2')[1]
    assert content == "asdf", repr(content)

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

    client.execute("poweroff", check_return=False)

    console = wait_for_console_text(client, "reboot: Power down")

    assert "Failed unmounting" not in console, "Unmounting NFS cleanly failed, check console output"

    client.wait_for_shutdown()

  '';

})
