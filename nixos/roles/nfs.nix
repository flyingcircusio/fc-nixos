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
  # This mountpoint is hard coded in the agent in update.py to ensure
  # we catch required reboot situations when the mount unit changes.
  mountpoint = "/mnt/nfs/shared";

  # Workaround for DIR-155/ PL-133063: We need to use the same hostname as
  # written into /etc/hosts for resilience against resolver failures. This
  # currently deviates from the raw string provided by the directory.
  normaliseHostname = hostname:
    let hostPart = builtins.head (lib.splitString "." hostname);
    in
    if (config.networking.domain != null && hostPart != "")
      then "${hostPart}.${config.networking.domain}"
      else hostname;

  # This is a bit different than on Gentoo. We allow export to all nodes in the
  # RG, regardles of the node actually being a client.
  exportToClients =
    let
      flags = lib.concatStringsSep "," cfg.roles.nfs_rg_share.clientFlags;
      clientWithFlags = c: "${normaliseHostname c.node}(${flags})";
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
        "${mountpoint}" = {
          device = "${normaliseHostname service.address}:${export}";
          fsType = "nfs4";
          #############################################################
          # WARNING: those settings are DUPLICATED in tests/nfs.nix to
          # work around a deficiency of the test harness.
          #############################################################
          options = [
            "rw"
            "auto"
            # Retry infinitely
            "hard"
            # perform mount unit activation in background to avoid
            # blocking nixos-rebuild switches if the server isn't
            # responsive at that point in time.
            "x-systemd.automount"
            # Start over the retry process after 10 tries
            "retrans=10"
            # Start with a 3s (30 deciseconds) interval and add 3s as linear
            # backoff
            "timeo=30"
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
