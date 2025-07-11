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

  fsInfo =
    fs:
    lib.pipe fs [
      (lib.mapAttrsToList (
        k: v: [
          k
          v
        ]
      ))
      lib.flatten
      (lib.concatStringsSep "\n")
      (pkgs.writeText "fsinfo")
    ];
in
{
  options = with lib; {
    flyingcircus.initrd = {
      upgradeXFS = lib.mkOption {
        description = ''
          Call xfs_admin -O with the specified devices and features before mounting.
          :::{.warning}
          Do not modify these light-heartedly. Changing xfs parameters can
          take several (tens of) minutes at the next boot, depending on the number of inodes.
          :::
        '';
        type = with lib.types; attrsOf (listOf (strMatching "[^=]+=[01]"));
        default = { };
        example = {
          "/dev/disk/by-label/root" = [ "bigtime=1" ];
        };
      };
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
    (lib.mkIf (cfg.upgradeXFS != { }) {
      boot.initrd = {
        extraUtilsCommands = ''
          copy_bin_and_libs ${pkgs.xfsprogs}/bin/xfs_admin
          copy_bin_and_libs ${pkgs.xfsprogs}/bin/xfs_info

          copy_bin_and_libs ${pkgs.xfsprogs}/bin/xfs_db
          copy_bin_and_libs ${pkgs.xfsprogs}/bin/xfs_spaceman
        '';

        extraUtilsCommandsTest = ''
          # from nixos/modules/tasks/filesystems/xfs.nix
          sed -i -e 's,^#!.*,#!'$out/bin/sh, $out/bin/xfs_admin $out/bin/xfs_info
          export PATH=$out/bin:$PATH
          $out/bin/xfs_admin -V
          $out/bin/xfs_info -V
        '';

        postDeviceCommands =
          let
            fName = f: lib.head (lib.splitString "=" f);
            fState = f: lib.last (lib.splitString "=" f);
            invert = f: "${fName f}=${if fState f == "0" then "1" else "0"}";
            upgradeXFS = lib.mapAttrs (
              _: v:
              (
                (lib.concatMap (f: [
                  (invert f)
                  f
                ]) v)
              )
              ++ [ "" ]
            ) cfg.upgradeXFS;
          in
          ''
            exec 3< ${fsInfo upgradeXFS}
            while read -u 3 device; do
              INFO=$(xfs_info "$device")
              while read -u 3 oldFeature; do
                if [ -z "$oldFeature" ]; then
                  break
                fi
                read -u 3 newFeature
                if echo "$INFO" | grep "$oldFeature"; then
                  # xfs_admin does not always apply all features if they are specified as a list
                  xfs_repair -n "$device" && xfs_admin -O "$newFeature" "$device"
                fi
              done
            done
          '';
      };
    })

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

        postMountCommands = lib.mkBefore ''
          QEMU_DIR="/mnt-root${qemuStateDir}"
          ENC_PATH="/mnt-root${config.flyingcircus.encPath}"
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
    })

    (lib.mkIf (cfg.formatXFS != { }) {
      assertions =
        let
          shared = lib.attrNames (lib.intersectAttrs cfg.formatXFS cfg.upgradeXFS);
        in
        [
          {
            assertion = lib.length shared == 0;
            message = "Can not format and upgrade at the same time. Offending entries: ${lib.concatStringsSep ", " shared}";
          }
        ];

      boot.initrd = {
        extraUtilsCommands = ''
          copy_bin_and_libs ${pkgs.xfsprogs}/bin/mkfs.xfs
        '';

        postMountCommands = ''
          exec 3< ${fsInfo cfg.formatXFS}
          while read -u 3 device; do
            read -u 3 options
            mkfs.xfs -f $options "$device"
            udevadm trigger "$device"
          done
        '';
      };
    })
  ];
}
