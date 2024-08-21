{ lib, pkgs, config, options, ... }:

let
  fclib = config.fclib;
  keysMountDir = "/mnt/keys";
  check_key_file = pkgs.writeShellScript "check_key_file" ''

      if [ ! -d ${keysMountDir} ]; then
        echo "Key directory ${keysMountDir} does not exist. Check not needed."
        exit 0
      fi

      if ! ${pkgs.util-linux}/bin/findmnt "${keysMountDir}" > /dev/null; then
        echo "error: ${keysMountDir} not mounted. Aborting."
        exit 2
      fi

      KF_PATH="${keysMountDir}/$(${pkgs.inetutils}/bin/hostname).key"
      if [ ! -s "$KF_PATH" ]; then
        echo "error: disk encryption keyfile is empty or does not exist. Aborting."
        exit 2
      fi

      KF_PERMS="$(${pkgs.coreutils}/bin/stat -L -c '%a %G %U' $KF_PATH)"
      if [ "$KF_PERMS" != "600 root root" ]; then
        echo "error: disk encryption keyfile has permissions $KF_PERMS, but should be root-accessible only. Aborting."
        exit 2
      fi

      exit 0
    '';
  cephPkgs = fclib.ceph.mkPkgs "nautilus";  # FIXME: just a workaround
  check_luks_cmd = "${cephPkgs.fc-ceph}/bin/fc-luks check '*'";
in
{

  options = {
    flyingcircus.infrastructure.fullDiskEncryption.fsOptions = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      default =  {
        device = "/dev/vgkeys/keys";
        fsType = "xfs";
        options = [ "nofail" "auto" "noexec" "nosuid" "nodev" "nouser"];
        neededForBoot = false;    # change this when introducing rootfs encryption
      };
    };
  };

  config = lib.mkIf (config.flyingcircus.infrastructureModule == "flyingcircus-physical" ||
    config.flyingcircus.infrastructureModule == "testing"
    )
  {
      environment.systemPackages = with pkgs; [
        cryptsetup
        # FIXME: isolate fc-luks tooling into separate package
        cephPkgs.fc-ceph
      ];

      flyingcircus.services.sensu-client.checks = {
        keystickMounted = {
          notification = "USB stick with disk encryption keys is mounted and keyfile is readable.";
          interval = 60;
          command = "sudo ${check_key_file}";
        };
        noSwap = {
          notification = "Machine does not use swap to arbitrarily persist memory pages with sensitive data.";
          interval = 60;
          command = toString (pkgs.writeShellScript "noSwapCheck" ''
            # /proc/swaps always has a header line
            if [ $(${pkgs.coreutils}/bin/cat /proc/swaps | ${pkgs.coreutils}/bin/wc -l) -ne 1 ]; then
              exit 1
            fi
          '');
        };
        luksParams = {
          notification = "LUKS Volumes use expected parameters.";
          interval = 3600;
          command = "sudo ${check_luks_cmd}";
        };
      };

      flyingcircus.passwordlessSudoRules = [{
        commands = [(toString check_key_file) check_luks_cmd];
        groups = ["sensuclient"];
      }];

      fileSystems.${keysMountDir} = config.flyingcircus.infrastructure.fullDiskEncryption.fsOptions;
  };

}
