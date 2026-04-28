import ./make-test-python.nix (
  {
    pkgs,
    lib,
    testlib,
    ...
  }:
  {
    name = "initrd";

    nodes.machine =
      { config, pkgs, ... }:
      {
        imports = [
          ../nixos
          ../nixos/roles
          (testlib.fcConfig { net.fe = false; })
        ];

        virtualisation.useDefaultFilesystems = false;
        virtualisation.emptyDiskImages = [
          5000 # tmp
          10 # cidata
        ];

        virtualisation.fileSystems = {
          "/" = {
            device = "/dev/disk/by-label/root";
            fsType = "xfs";
          };
          "/tmp" = {
            device = "/dev/disk/by-partlabel/tmp";
            fsType = "xfs";
            noCheck = true;
          };
        };
        flyingcircus.initrd = {
          formatXFS = {
            # nrext64 requires kernel 6.5+
            # exchange-range, parent pointers requires kernel 6.10+ and is not recommended until kernel 6.18+
            "/dev/disk/by-partlabel/tmp" =
              "-L tmp -q -K -m crc=1,finobt=1,bigtime=1 -i nrext64=0,exchange=0 -n parent=0 -d su=4m,sw=1";
          };
          collectQemuData = true;
        };

        # systemd initrd expects the root device to be partitioned correctly, systemd repart handles this.
        boot.initrd.systemd.repart = {
          enable = true;
          device = "/dev/vda";
          empty = "allow";
        };
        systemd.repart.partitions = {
          "00-root" = {
            Type = "linux-generic";
            Format = "xfs";
            Label = "root";
          };
        };
        boot.initrd.systemd.extraBin = {
          blkid = "${pkgs.util-linux}/bin/blkid";
          sgdisk = "${pkgs.gptfdisk}/bin/sgdisk";
        };
        boot.initrd.systemd.services."fc-build-filesystems" = {
          wantedBy = [ "initrd.target" ];
          before = [
            "initrd-root-fs.target"
          ];
          after = [
            "initrd-root-device.target"
            "basic.target"
          ];
          script = ''
            FSTYPE=$(blkid -o value -s TYPE /dev/vdb1 || true)
            if test -z "$FSTYPE"; then
              sgdisk -o /dev/vdb
              sgdisk -a 8192 -n 1:8192:0 -c "1:tmp" -t 1:8300 /dev/vdb
              mkfs.xfs -L tmp /dev/vdb1

              sgdisk -o /dev/vdc
              sgdisk -n 1:: -c "1:cidata" -t 1:8300 /dev/vdc
              mkfs.vfat -n "cidata" /dev/vdc1
            fi
          '';
        };

        flyingcircus.services.sensu-client.enable = lib.mkForce false;
      };

    testScript = ''
      machine.start()

      def reboot():
        machine.succeed("sync")
        machine.crash()
        machine.start()
        machine.succeed('mkdir -p /cidata')
        machine.succeed('mount /dev/disk/by-label/cidata /cidata')

      with subtest("xfs upgrade/format"):
        assert "drwxrwxrwt" in (r := machine.succeed('stat /tmp')), r

      with subtest("/tmp data"):
        machine.succeed('mkdir /tmp/fc-data')
        machine.succeed('echo -n "guest-props" > /tmp/fc-data/qemu-guest-properties-booted')
        machine.succeed('echo -n "bin-gen" > /tmp/fc-data/qemu-binary-generation-booted')
        machine.succeed('echo -n "enc" > /tmp/fc-data/enc.json')
        reboot()
        assert machine.succeed('cat /var/lib/qemu/qemu-guest-properties-booted') == "guest-props"
        machine.fail('stat /var/lib/qemu/qemu-binary-generation-booted')
        assert machine.succeed('cat /etc/nixos/enc.json') == "enc"

      with subtest("prefer /cidata data"):
        machine.succeed('mkdir /tmp/fc-data')
        machine.succeed('echo -n "guest-props" > /tmp/fc-data/qemu-guest-properties-booted')
        machine.succeed('echo -n "bin-gen" > /tmp/fc-data/qemu-binary-generation-booted')
        machine.succeed('echo -n "enc2" > /tmp/fc-data/enc.json')
        machine.succeed('mkdir /cidata/fc-data')
        machine.succeed('echo -n "guest-props2" > /cidata/fc-data/qemu-guest-properties-booted')
        reboot()
        assert machine.succeed('cat /var/lib/qemu/qemu-guest-properties-booted') == "guest-props2"
        assert machine.succeed('cat /etc/nixos/enc.json') == "enc" # OLD

      with subtest("only /cidata data"):
        machine.succeed('echo -n "guest-props3" > /cidata/fc-data/qemu-guest-properties-booted')
        machine.succeed('echo -n "enc3" > /cidata/fc-data/enc.json')
        reboot()
        assert machine.succeed('cat /var/lib/qemu/qemu-guest-properties-booted') == "guest-props3"
        assert machine.succeed('cat /etc/nixos/enc.json') == "enc"
    '';
  }
)
