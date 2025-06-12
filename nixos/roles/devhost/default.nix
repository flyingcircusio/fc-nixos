{ config, lib, ... }:

let
  cfg = config.flyingcircus.roles.devhost;
  fclib = config.fclib;
in
{
  imports = [
    ./vm.nix
    (lib.mkRemovedOptionModule [
      "flyingcircus"
      "roles"
      "devhost"
      "cleanupContainers"
    ] "Automatic cleanup of VMs is not supported right now.")
  ];

  options = {
    flyingcircus.roles.devhost = {

      enable = lib.mkEnableOption "Enable our development host for slim virtual machines";

      publicAddress = lib.mkOption {
        description = "Name of the public address of this development server.";
        type = lib.types.str;
        default = "example.com";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      flyingcircus.roles.webgateway.enable = true;

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = fclib.mkOverridePlatformModule 1;
        # Increase inotify limits to avoid running out of them when
        # running many containers:
        # https://forum.proxmox.com/threads/failed-to-allocate-directory-watch-too-many-open-files.28700/
        "fs.inotify.max_user_instances" = 512;
        "fs.inotify.max_user_watches" = 16384;
      };
      networking.nat.internalInterfaces = [ "ve-+" ];
    })
  ];
}
