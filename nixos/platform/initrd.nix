{
  config,
  lib,
  options,
  utils,
  pkgs,
  ...
}:
let
  cfg = config.flyingcircus.initrd;
  qemuStateDir = "/var/lib/qemu";
in
{
  options = with lib; {
    flyingcircus.initrd = {
      formatXFS = lib.mkOption {
        description = ''
          Format device with mkfs.xfs options before mounting.
          The resulting filesystem can not be used with fileSystems.<name>.neededForBoot=true
        '';
        type = with lib.types; attrsOf str;
        default = { };
        example = {
          "/dev/disk/by-partlabel/tmp" = "-L tmp -q -K -m crc=1 -d su=4m,sw=1";
        };
      };
      collectQemuData = lib.mkOption {
        description = "Copy the qemu boot time properties into ${qemuStateDir}.";
        type = with lib.types; bool;
        default = false;
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.collectQemuData {
      assertions =
        let
          ls = fss: lib.concatMapStringsSep ", " (x: x.mountPoint) fss;
          parentAssertion =
            path:
            let
              parents = lib.filter (
                fs: lib.hasPrefix fs.mountPoint path && !utils.fsNeededForBoot fs
              ) config.system.build.fileSystems;
            in
            {
              assertion = lib.length parents == 0;
              message = "Every parent of ${path} needs neededForBoot=true. Offending entries: ${ls parents}";
            };
        in
        map parentAssertion [
          qemuStateDir
          config.flyingcircus.encPath
        ];

      boot.supportedFilesystems = [
        "vfat"
        "xfs"
      ];

      boot.initrd = {
        supportedFilesystems = [
          "vfat"
          "xfs"
        ];

        systemd.services."fc-extract-fc-data" = {
          serviceConfig.Type = "oneshot";
          wantedBy = [ "initrd.target" ];
          after = [
            "initrd-fs.target"
          ];
          before = [
            "initrd.target"
          ]
          ++ lib.optionals (cfg.formatXFS != { }) [
            "fc-format-xfs.service"
          ];
          script = ''
            QEMU_DIR="/sysroot${qemuStateDir}"
            ENC_PATH="/sysroot${config.flyingcircus.encPath}"

            mkdir -p $QEMU_DIR
            mkdir -p $(dirname $ENC_PATH)
            mkdir -m 0755 -p /cidata
            for args in "cidata vfat" "tmp xfs"; do
              set $args
              if [ ! -e /dev/disk/by-label/$1 ]; then
                continue
              fi
              mount -n -t $2 -o ro /dev/disk/by-label/$1 /cidata
              if [ ! -d /cidata/fc-data ]; then
                umount -n /cidata
                continue
              fi
              if [ ! -e "$ENC_PATH" ] && [ -e "/cidata/fc-data/enc.json" ]; then
                cp /cidata/fc-data/enc.json "$ENC_PATH"
              fi
              if [ -e /cidata/fc-data/qemu-guest-properties-booted ]; then
                cp /cidata/fc-data/qemu-guest-properties-booted "$QEMU_DIR"
              elif [ -e /cidata/fc-data/qemu-binary-generation-booted ]; then
                cp /cidata/fc-data/qemu-binary-generation-booted "$QEMU_DIR"
              fi
              umount -n /cidata
              break
            done
          '';
        };
      };
    })

    (lib.mkIf (cfg.formatXFS != { }) {
      boot.initrd = {
        supportedFilesystems = [ "xfs" ];
        systemd.services."fc-format-xfs" = {
          serviceConfig.Type = "oneshot";
          wantedBy = [ "initrd.target" ];
          before = [
            "initrd.target"
          ];
          after = [
            "initrd-fs.target"
          ];
          script = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (device: options: ''
              mkfs.xfs -f ${options} "${device}"
            '') cfg.formatXFS
          );
        };
      };
    })
  ];
}
