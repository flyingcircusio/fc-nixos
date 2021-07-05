import ./make-test-python.nix ({ ... }:

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

in {
  name = "nfs";
  nodes = {
    client =
      { lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        config = {
          flyingcircus.roles.nfs_rg_client.enable = true;
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
                "intr"
                "rsize=8192"
                "wsize=8192"
                "noauto"
                "x-systemd.automount"
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

    server.start()
    server.wait_for_unit("nfs-server")
    server.wait_for_unit("nfs-idmapd")
    server.wait_for_unit("nfs-mountd")
    client.start()

    server.succeed("chown test ${sdir}")

    # user test on server should be able to write to shared dir
    server.succeed("sudo -u test echo test_on_server > ${sdir}/test")

    # share should be mounted upon access
    client.succeed("cd ${cdir}")
    client.wait_for_unit("mnt-nfs-shared.mount")

    # The commented code below was originaly writen in perl and was converted to python.
    # It ist not tested and the comment below may not apply anymore!
    # XXX: results in permission denied, why?
    #client.succeed("grep test_on_server ${cdir}/test")

    #client.succeed("sudo -u test echo test_on_client > $cdir/test")
    #server.succeed("grep test_on_client $sdir/test")

    #client.fail("echo from_root_user > $cdir/test")
    #server.succeed("grep from_test_user $sdir/test")
  '';

})
