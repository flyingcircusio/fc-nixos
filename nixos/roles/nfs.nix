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
  mountpoint = "/mnt/nfs";
  
  # This is a bit different than on Gentoo. We allow export to all nodes in the
  # RG, regardles of the node actually being a client.
  exportToClients =
    let
      flags = "rw,sync,root_squash,no_subtree_check";
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
    };
  };

  config = lib.mkMerge [
    {
      # Typical services that should be started after and shut down before
      # we try to unmount NFS.
      # See https://yt.flyingcircus.io/issue/PL-129954 for a discussion about
      # this.
      # We always enable this because customers might enable NFS 
      # through other means than our roles.
      systemd.services.httpd.after = [ "remote-fs.target" ];
      systemd.services.nginx.after = [ "remote-fs.target" ];
    }

    (lib.mkIf (cfg.roles.nfs_rg_client.enable && service != null) {
      fileSystems = {
        # WARNING: those settings are duplicated in the tests to
        # fix a deficiency of the test harness.
        "${mountpoint}/shared" = {
          device = "${service.address}:${export}";
          fsType = "nfs4";
          options = [
            "rw"
            "soft"
            "rsize=8192"
            "wsize=8192"
            "nfsvers=4"
          ];
          noCheck = true;
        };
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
    })

  ];
}
