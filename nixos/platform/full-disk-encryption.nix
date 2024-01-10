{ lib, pkgs, config, options, ... }:

let
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
      ];

      flyingcircus.services.sensu-client.checks.keystickMounted = {
        notification = "USB stick with disk encryption keys is mounted and keyfile is readable.";
        interval = 60;
        command = "sudo ${check_key_file}";
      };

      flyingcircus.passwordlessSudoRules = [{
        commands = [(toString check_key_file)];
        groups = ["sensuclient"];
      }];

      fileSystems.${keysMountDir} = config.flyingcircus.infrastructure.fullDiskEncryption.fsOptions;
  };

}
