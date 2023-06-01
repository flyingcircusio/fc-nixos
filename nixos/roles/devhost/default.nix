{ config, lib, pkgs, ... }:

with builtins;
let
  cfg = config.flyingcircus.roles.devhost;
  fclib = config.fclib;

in
{
  imports = [
    ./container.nix
    ./vm.nix
  ];

  options = {
    flyingcircus.roles.devhost = {

      enable = lib.mkEnableOption "Enable our container-based development host";

      virtualisationType = lib.mkOption {
        type = lib.types.enum [ "vm" "container" ];
        default = "container";
      };

      supportsContainers = fclib.mkDisableContainerSupport;

      enableAliasProxy = lib.mkOption {
        description = "Enable HTTPS-Proxy for containers and their aliases.";
        type = lib.types.bool;
        default = !cfg.testing;  # Disable on testing by default.
      };

      publicAddress = lib.mkOption {
        description = "Name of the public address of this development server.";
        type = lib.types.str;
        default = "example.com";
      };

      cleanupContainers = lib.mkOption {
        description = "Whether to automatically shut down and destroy unused containers.";
        type = lib.types.bool;
        default = true;
      };

      testing = lib.mkEnableOption "Enable testing mode that routinely creates and destroys containers and reports status to sensu.";

      testingChannelURL = lib.mkOption {
        description = "URL to an hydra build (see directory) that containers use.";
        type = lib.types.str;
        default = config.flyingcircus.enc.parameters.environment_url;
      };

    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      flyingcircus.roles.webgateway.enable = true;

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        # Increase inotify limits to avoid running out of them when
        # running many containers:
        # https://forum.proxmox.com/threads/failed-to-allocate-directory-watch-too-many-open-files.28700/
        "fs.inotify.max_user_instances" = 512;
        "fs.inotify.max_user_watches" = 16384;
      };
      networking.nat.internalInterfaces = ["ve-+"];
    })
  ];
}
