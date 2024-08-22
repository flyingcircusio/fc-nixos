import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:
let
  migrationScript = pkgs.writeShellScript "backy-reencrypter" ''
    PLAIN_DEVICE="/dev/disk/by-id/md-name-legacyBacky:md0"
    systemctl stop backy.service
    umount /srv/backy
    systemd-run --property=Type=oneshot -r -u backy-reencrypt cryptsetup -q reencrypt --encrypt  --header /srv/backy.luks --pbkdf=argon2id -d /mnt/keys/$(hostname).key --resilience=journal $PLAIN_DEVICE backy
    sleep 30
    mount /dev/mapper/backy /srv/backy
    systemctl start backy.service
    # create an early header backup
    cp /srv/backy.luks /mnt/keys/
  '';
  mkMachine = backyserverRoleConfig: {config, lib, ...}:{
    imports = [
      ../nixos
      ../nixos/roles
      (testlib.fcConfig { net.fe = false; })
    ];

    flyingcircus.roles.backyserver = {
      enable = true;
    } // backyserverRoleConfig;
    flyingcircus.services.ceph.client.enable = lib.mkForce false;
    flyingcircus.services.consul.enable = lib.mkForce false;
    flyingcircus.enc.name = "machine";

    virtualisation.emptyDiskImages = [1000 1000 1000 1000 1000 1100];
    # :( Work-around the split between qemu-built systems and regular systems.
    virtualisation.fileSystems."/mnt/keys" = config.flyingcircus.infrastructure.fullDiskEncryption.fsOptions;
    virtualisation.fileSystems."/srv/backy" = config.flyingcircus.roles.backyserver.fsOptions;
    # Cotherwise fc-luks OOMs
    virtualisation.memorySize = 1200;
  };

in
{
  name = "backy-volumes";

  nodes = {
    # as specialisations do not persist reboots, just sequentially use 2 different machines with slightly adjusted config
    legacyBacky = mkMachine {
      blockDevice = "/dev/disk/by-id/md-name-legacyBacky:md0";
      externalCryptHeader = true;
    };
    newBacky = mkMachine {};
  };
  testScript = {nodes, ...}:
    let
    check_luksParams = testlib.sensuCheckCmd nodes.newBacky "luksParams";
    in ''
    from time import sleep


    def setupKeystore(machine):
        with subtest("Initialise keystore"):
          machine.succeed("fc-luks keystore create /dev/vdg > /dev/kmsg 2>&1")
          print(machine.succeed("lsblk"))
          machine.succeed("${pkgs.util-linux}/bin/findmnt /mnt/keys > /dev/kmsg 2>&1")

    def test_reboot_automount(machine):
      with subtest("automount of volume works at boot"):
        machine.execute("systemctl poweroff --force")
        machine.wait_for_shutdown()
        machine.start()
        machine.wait_for_unit("local-fs.target")

        # The target only pulls the mount unit in for activation, but does not imply a chronological ordering.
        # We still need to wait for the mount to happen.
        machine.wait_until_succeeds("${pkgs.util-linux}/bin/findmnt /srv/backy > /dev/kmsg 2>&1")
        print(machine.succeed("lsblk"))
        print(machine.succeed('cat /etc/crypttab'))
        print(machine.succeed('cat /etc/fstab'))
        print(machine.succeed('ls -l /dev/disk/by-id/'))
        print(machine.execute('systemctl status srv-backy.mount')[1])

        machine.succeed('lsblk | egrep "crypt[[:space:]]+/srv/backy"')

    print(legacyBacky.succeed("lsblk"))
    # preparing an unencrypted legacy RAID setup
    legacyBacky.succeed(f"mdadm --create /dev/md/md0 --level=6 --raid-devices=4 /dev/vdb /dev/vdc /dev/vdd /dev/vde > /dev/kmsg 2>&1")
    legacyBacky.succeed(f"mdadm --add /dev/md/md0 /dev/vdf > /dev/kmsg 2>&1")

    print(legacyBacky.succeed("ls -l /dev/disk/by-id/"))

    legacyBacky.succeed(f"mkfs.xfs -L backy /dev/md/md0 > /dev/kmsg 2>&1")
    legacyBacky.execute("systemctl daemon-reload")
    legacyBacky.succeed("systemctl start srv-backy.mount > /dev/kmsg 2>&1")
    print(legacyBacky.succeed("lsblk"))

    setupKeystore(legacyBacky)

    with subtest("manual reencryptioon of a legacy device:"):
      legacyBacky.succeed("${pkgs.util-linux}/bin/findmnt /srv/backy > /dev/kmsg 2>&1")
      legacyBacky.execute("echo FOOTEST > /srv/backy/testfile")
      legacyBacky.succeed("${migrationScript}")
      legacyBacky.wait_for_unit("backy-reencrypt.service")
      print(legacyBacky.execute('systemctl status backy-reencrypt.service')[1])
      legacyBacky.succeed('echo -e "newphrase\ny\n" | setsid -w fc-luks keystore rekey --slot=admin backy > /dev/kmsg 2>&1')
      legacyBacky.succeed("${pkgs.util-linux}/bin/findmnt /srv/backy > /dev/kmsg 2>&1")
      legacyBacky.succeed("grep FOOTEST /srv/backy/testfile")

    test_reboot_automount(legacyBacky)

    legacyBacky.execute("systemctl poweroff --force")
    legacyBacky.wait_for_shutdown()

    # test fc-luks backup create
    setupKeystore(newBacky)

    with subtest("Creating new backy volume from scratch"):
      newBacky.succeed('echo -e "adminphrase\ny\n" | setsid -w fc-luks backup create /dev/vdb /dev/vdc /dev/vdd /dev/vde /dev/vdf > /dev/kmsg 2>&1')
      newBacky.succeed("${pkgs.util-linux}/bin/findmnt /srv/backy > /dev/kmsg 2>&1")

    test_reboot_automount(newBacky)

    with subtest("Smoke test for LUKS metadata check"):
      newBacky.succeed("(export PATH='${pkgs.sudo}/bin/'; ${check_luksParams} > /dev/kmsg 2>&1 )")
  '';
})
