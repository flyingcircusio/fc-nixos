import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  {
    name = "fde-tooling";
    nodes = {
      host1 =
        { config, lib, ... }:
        {

          virtualisation.emptyDiskImages = [
            2000 # vdb - key stick
            2000 # vdc - backup disk 1
            2000 # vdd - backup disk 2
            2000 # vde - backup disk 3
            2000 # vdf - backup disk 4
            2000 # vdg - backup disk 5
          ];
          imports = [ (testlib.fcConfig { }) ];

          # :( Work-around the split between qemu-built systems and regular systems.
          virtualisation.fileSystems."/mnt/keys" =
            config.flyingcircus.infrastructure.fullDiskEncryption.fsOptions;
          virtualisation.fileSystems."/srv/backy" = config.flyingcircus.roles.backyserver.fsOptions;

          flyingcircus.infrastructure.fullDiskEncryption.enable = true;
          flyingcircus.roles.backyserver.enable = true;
          flyingcircus.services.ceph.client.enable = lib.mkForce false;
          flyingcircus.services.consul.enable = lib.mkForce false;
          flyingcircus.enc.name = "machine";
        };

    };

    testScript =
      { nodes, ... }:
      let
        check_key_file_cmd = testlib.sensuCheckCmd nodes.host1 "keystickMounted";
      in
      ''
        import time
        import json

        start_all()

        def show(host, cmd):
            result = host.execute(cmd)[1]
            print(result)
            return result

        show(host1, "df -h")
        show(host1, "lsblk")

        with subtest("Initialize keystore"):
          # check succeeds as "not needed" as long as /mnt/keys does not exist
          host1.succeed("${check_key_file_cmd} > /dev/kmsg 2>&1")
          host1.succeed("fc-luks keystore create /dev/vdb > /dev/kmsg 2>&1")
          host1.succeed("${check_key_file_cmd} > /dev/kmsg 2>&1")

        with subtest("Initialize backy volume"):
          host1.succeed('echo -e "adminphrase\ny\n" | setsid -w fc-luks backup create /dev/vdc /dev/vdd /dev/vde /dev/vdf /dev/vdg > /dev/kmsg 2>&1')
          show(host1, "df -h")
          show(host1, "lsblk")
          show(host1, "mount")
          host1.succeed("mount /srv/backy")

        with subtest("Destroy and re-create the keystore, rekey all volumes"):
          host1.succeed("${pkgs.lsof}/bin/lsof | grep keys >/dev/kmsg 2>&1 || true")
          host1.succeed("fc-luks keystore destroy --no-overwrite > /dev/kmsg 2>&1")
          #breakpoint()
          host1.succeed("fc-luks keystore create /dev/vdb > /dev/kmsg 2>&1")
          host1.succeed('echo -e "adminphrase\ny\n" | setsid -w fc-luks keystore rekey "*" > /dev/kmsg 2>&1')
          host1.succeed('echo -e "newphrase\ny\n" | setsid -w fc-luks keystore rekey --slot=admin "*" > /dev/kmsg 2>&1')
          host1.succeed('echo -e "newphrase\n" | setsid -w fc-luks keystore rekey "*" > /dev/kmsg 2>&1')

        with subtest("Verify keystore automount on boot"):
          host1.execute("systemctl poweroff --force")
          host1.wait_for_shutdown()
          host1.start()
          host1.wait_for_unit("local-fs.target")
          show(host1, "mount")
          host1.execute("sleep 5")
          show(host1, "mount")
          show(host1, "systemctl status multi-user.target")
          show(host1, "lsblk")
          show(host1, "cat /etc/fstab")
          host1.succeed("${pkgs.util-linux}/bin/findmnt /mnt/keys > /dev/kmsg 2>&1")

        with subtest("Verify all services are up after a reboot"):
          show(host1, "systemctl status -l backy.service")
          host1.wait_for_unit("backy.service")

        with subtest("`fc-luks keystore test-open` verifies that volumes can be unlocked"):
          host1.succeed('echo -e "newphrase\n" | setsid -w fc-luks keystore test-open "*" > /dev/kmsg 2>&1')
          # no volume matched
          host1.fail('echo -e "newphrase\n" | setsid -w fc-luks keystore test-open "asdfhjkl" > /dev/kmsg 2>&1')
          # wrong admin passphrase (will also modify the fingerprint)
          host1.fail('echo -e "wrongphrase\ny\n" | setsid -w fc-luks keystore test-open "*" > /dev/kmsg 2>&1')
          # wrong local keyfile (will correct admin keyphrase fingerprint again)
          host1.execute("mv /mnt/keys/host1.key{,.bak}; echo garbage > /mnt/keys/host1.key")
          host1.fail('echo -e "newphrase\ny\n" | setsid -w fc-luks keystore test-open "*" > /dev/kmsg 2>&1')
          host1.execute("mv /mnt/keys/host1.key{.bak,}")

        with subtest("The check discovers non-conforming host key conditions"):
          host1.execute('chmod o+rw /mnt/keys/*')
          host1.fail("${check_key_file_cmd} > /dev/kmsg 2>&1")
          host1.execute('rm /mnt/keys/*')
          host1.fail("${check_key_file_cmd} > /dev/kmsg 2>&1")
      '';
  }
)
