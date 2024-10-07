# NFS resource group share.
# Note that activating both nfs_rg_share and nfs_rg_client currently fails due
# to a race condition. Re-run fc-manage in this case.
# RG shares exported from a NixOS server cannot be written to by service users
# running Gentoo and vice versa.
{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;
  serviceName = "nfs_rg_share-server";

  service = fclib.findOneService serviceName;
  serviceClients = fclib.findServiceClients serviceName;

  export = "/srv/nfs/shared";
  mountpoint = "/mnt/nfs/shared";

  # This is a bit different than on Gentoo. We allow export to all nodes in the
  # RG, regardles of the node actually being a client.
  exportToClients =
    let
      flags = lib.concatStringsSep "," cfg.roles.nfs_rg_share.clientFlags;
      clientWithFlags = c: "${c.node}(${flags})";
    in
      lib.concatMapStringsSep " " clientWithFlags serviceClients;

in
{
  options = with lib; {
    flyingcircus.roles.nfs_rg_client = {
      enable = mkEnableOption ''
        Enable the Flying Circus nfs client role.

        This mounts /srv/nfs/shared from the server to /mnt/nfs/shared.
      '';
      supportsContainers = fclib.mkEnableContainerSupport;
    };

    flyingcircus.roles.nfs_rg_share = {
      enable = mkEnableOption ''
        Enable the Flying Circus nfs server role.

        This exports /srv/nfs/shared.
      '';
      supportsContainers = fclib.mkEnableContainerSupport;
      clientFlags = lib.mkOption {
          default = ["rw" "sync" "root_squash" "no_subtree_check"];
          type = with types; listOf str;
          description = ''
            Flags for each client's export rule.
          '';
        };

    };
  };

  config = lib.mkMerge [
    # Typical services that should be started after and shut down before
    # we try to unmount NFS.
    # See https://yt.flyingcircus.io/issue/PL-129954 for a discussion about
    # this.
    # We always enable this because customers might enable NFS
    # through other means than our roles.
    {
      systemd.targets.remote-fs.before = [
        "httpd.service"
        "nginx.service"
      ];
    }

    (lib.mkIf (cfg.roles.nfs_rg_client.enable && service != null) {
      fileSystems = {
        # WARNING: those settings are duplicated in the tests to
        # fix a deficiency of the test harness.
        "${mountpoint}" = {
          device = "${service.address}:${export}";
          fsType = "nfs4";
          options = [
            "rw"
            "noauto"
            "soft"
            "rsize=8192"
            "wsize=8192"
            "nfsvers=4"
          ];
          noCheck = true;
        };
      };

      # SystemD strictly doesn't want to implement any kind of retry-logic
      # around mount units. So lets not use them.
      systemd.services.mount-nfs-shared = {
          path = [ pkgs.util-linux ];
          wantedBy = [ "remote-fs.target" ];
          before = [ "remote-fs.target" ];
          reloadIfChanged=true;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          reload = ''
            set -x
            while ! mount -o remount ${mountpoint}; do
              sleep 5;
            done
          '';
          script = ''
            set -x
            while ! mountpoint ${mountpoint}; do
              mount ${mountpoint} || sleep 5
            done
          '';
      };

      systemd.tmpfiles.rules = [
        "d ${mountpoint}"
      ];
    })

    (lib.mkIf (cfg.roles.nfs_rg_share.enable && serviceClients != []) {
      services.nfs.server.enable = true;
      services.nfs.server.exports = ''
        ${export}  ${exportToClients}
      '';
      system.activationScripts.nfs_rg_share = ''
        install -d -g service -m 775 ${export}
        ${pkgs.nfs-utils}/bin/exportfs -ra
      '';
      systemd.services.nfs-mountd.reloadIfChanged = true;
      systemd.services.nfs-server.reloadIfChanged = true;
      # reload script for nfs-mountd so that it does not fail when reloading
      systemd.services.nfs-mountd.reload = ''
        ${pkgs.nfs-utils}/bin/exportfs -ra
      '';
      systemd.services.nfs-server.serviceConfig.ExecStartPre = let
        exportScript = pkgs.writeShellScript "ensure-exports" ''
          echo "Retrying failed exports .."
          while exportfs -r 2>&1 | grep Fail; do
            sleep 5
          done
          echo "All exports successful."
          '';
      in
        lib.mkForce exportScript;

    })

  ];
}
