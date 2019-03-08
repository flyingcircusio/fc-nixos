{ pkgs
, lib

, # The NixOS configuration to be installed onto the disk image.
  config

, # The size of the disk, in megabytes.
  diskSize

  # The files and directories to be placed in the target file system.
  # This is a list of attribute sets {source, target} where `source'
  # is the file system object (regular file or directory) to be
  # grafted in the file system at path `target'.
, contents ? []

, # Type of partition table to use; either "legacy", "efi", or "none".
  # For "efi" images, the GPT partition table is used and a mandatory ESP
  #   partition of reasonable size is created in addition to the root partition.
  #   If `installBootLoader` is true, GRUB will be installed in EFI mode.
  # For "legacy", the msdos partition table is used and a single large root
  #   partition is created. If `installBootLoader` is true, GRUB will be
  #   installed in legacy mode.
  # For "none", no partition table is created. Enabling `installBootLoader`
  #   most likely fails as GRUB will probably refuse to install.
  partitionTableType ? "efi"

, # the root filesystems fslabel (not partition label!)
  rootLabel ? "nixos"

, # The initial NixOS configuration file to be copied to
  # /etc/nixos/configuration.nix.
  configFile ? null

, # Shell code executed after the VM has finished.
  postVM ? ""

, name ? "nixos-disk-image"

, # Disk image format, one of qcow2, qcow2-compressed, vpc, raw.
  format ? "raw"

, # initial content of /root/.nix-defexprs/channels/nixos
  channelSources
}:

assert partitionTableType == "legacy" || partitionTableType == "efi" || partitionTableType == "none";

with lib;

let format' = format; in let

  format = if format' == "qcow2-compressed" then "qcow2" else format';

  compress = optionalString (format' == "qcow2-compressed") "-c";

  filename = "nixos." + {
    qcow2 = "qcow2";
    vpc   = "vhd";
    raw   = "img";
  }.${format};

  partitionDiskScript = { # switch-case
    legacy = ''
      parted --script $diskImage -- \
        mklabel msdos \
        mkpart primary ext4 1MiB -1
    '';
    efi = ''
      sgdisk $diskImage -o -a 2048 \
        -n 1:8192:0   -c 1:ROOT      -t 1:8300 \
        -n 2:2048:+1M -c 2:BIOS-BOOT -t 2:EF02
    '';
    none = "";
  }.${partitionTableType};

  nixpkgs = channelSources;

  binPath = with pkgs; makeBinPath (
    [ rsync
      utillinux
      parted
      gptfdisk
      xfsprogs
      lkl
      config.system.build.nixos-install
      config.system.build.nixos-enter
      nix
    ] ++ stdenv.initialPath);

  # I'm preserving the line below because I'm going to search for it across nixpkgs to consolidate
  # image building logic. The comment right below this now appears in 4 different places in nixpkgs :)
  # !!! should use XML.
  sources = map (x: x.source) contents;
  targets = map (x: x.target) contents;

  closureInfo = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel channelSources ]; };

  prepareImage = ''
    export PATH=${binPath}
    mkdir $out
    diskImage=nixos.raw
    truncate -s ${toString diskSize}M $diskImage

    ${partitionDiskScript}

    ${if partitionTableType != "none" then ''
      # Get start & length of the root partition in sectors to $START and $SECTORS.
      eval $(partx $diskImage -o START,SECTORS --nr 1 --pairs)
      startMB=$((START / 2048))
      sizeMB=$((SECTORS / 2048))
      # mkfs.xfs does not support --offset, so we must place a separately
      # generated XFS image into the main disk image.
      truncate -s ''${sizeMB}M rootfs.img
      mkfs.xfs -L ${rootLabel} rootfs.img
      dd if=rootfs.img of=$diskImage bs=1M seek=$startMB count=$sizeMB \
        conv=sparse,notrunc iflag=direct
      rm rootfs.img
    '' else ''
      mkfs.xfs -L ${rootLabel} $diskImage
    ''}

    root="$PWD/root"
    mkdir -p $root

    # Copy arbitrary other files into the image
    # Semi-shamelessly copied from make-etc.sh. I (@copumpkin) shall factor this stuff out as part of
    # https://github.com/NixOS/nixpkgs/issues/23052.
    set -f
    sources_=(${concatStringsSep " " sources})
    targets_=(${concatStringsSep " " targets})
    set +f

    for ((i = 0; i < ''${#targets_[@]}; i++)); do
      source="''${sources_[$i]}"
      target="''${targets_[$i]}"

      if [[ "$source" =~ '*' ]]; then
        # If the source name contains '*', perform globbing.
        mkdir -p $root/$target
        for fn in $source; do
          rsync -a --no-o --no-g "$fn" $root/$target/
        done
      else
        mkdir -p $root/$(dirname $target)
        if ! [ -e $root/$target ]; then
          rsync -a --no-o --no-g $source $root/$target
        else
          echo "duplicate entry $target -> $source"
          exit 1
        fi
      fi
    done

    export HOME=$TMPDIR

    # Provide a Nix database so that nixos-install can copy closures.
    export NIX_STATE_DIR=$TMPDIR/state
    nix-store --load-db < ${closureInfo}/registration

    echo "running nixos-install..."
    nixos-install --root $root --no-bootloader --no-root-passwd \
      --system ${config.system.build.toplevel} --channel ${channelSources} \
      --substituters ""

    echo "copying staging root to image..."
    cptofs ${optionalString (partitionTableType != "none") "-P 1"} -t xfs -i $diskImage $root/* /
  '';

in
pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand name
    { preVM = prepareImage;
      buildInputs = with pkgs; [ utillinux e2fsprogs dosfstools ];
      postVM = ''
        ${lib.optionalString (format != "raw") ''
          ${pkgs.qemu}/bin/qemu-img convert -f raw -O ${format} ${compress} $diskImage $out/${filename}
          diskImage=$out/${filename}
        ''}
        ${postVM}
      '';
      memSize = 1024;
    }
    ''
      export PATH=${binPath}:$PATH
      rootDisk=${if partitionTableType != "none" then "/dev/vda1" else "/dev/vda"}

      # Some tools assume these exist
      ln -s vda /dev/xvda
      ln -s vda /dev/sda

      mkdir /mnt
      mount $rootDisk /mnt

      # Install a configuration.nix
      mkdir -p /mnt/etc/nixos
      ${optionalString (configFile != null) ''
        cp ${configFile} /mnt/etc/nixos/configuration.nix
      ''}

      echo "configuring core system link, GRUB, etc..."
      NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot

      # The above scripts will generate a random machine-id and we don't want to bake a single ID into all our images
      rm -f /mnt/etc/machine-id

      umount -R /mnt
    ''
)
