{
  config,
  lib,
  pkgs,
  ...
}:

# This file needs to be kept (somewhat) in sync with our
# `tests/ceph-nautilus.nix` in the platform.
let
  fclib = config.fclib;
  testPackage = pkgs.fc.ceph.overrideAttrs (old: {
    version = "dev";
    # builtins.toPath (testPath + "/.")
    # for tests:
    src = /home/developer/fc-nixos/pkgs/fc/ceph/.;
  });
in
{
  flyingcircus.roles.ceph_osd = {
    enable = true;
    cephRelease = "pacific";
  };
  flyingcircus.roles.ceph_mon = {
    enable = true;
    cephRelease = "pacific";
    mgr.sendTelemetry = false;
  };
  flyingcircus.roles.ceph_rgw = {
    rgwInterface = "srv";
    cephRelease = "pacific";
  };
  flyingcircus.services.ceph.extraSettings = {
    monClockDriftAllowed = 10;
    osdPoolDefaultSize = 1;
    osdPoolDefaultMinSize = 1;
    monAllowPoolSizeOne = true;
    monWarnOnPoolNoRedundancy = false;
  };
  flyingcircus.services.ceph.client = {
    mons = [ "host1" ];
    network = fclib.network.srv;
    fsId = "20cd8cd8-4854-469b-a9c0-daa8ce4c0dff";
  };
  flyingcircus.static.ceph.fsids.test.test = "d118a9a4-8be5-4703-84c1-87eada2e6b60";

  # Try to disable as many cronjobs as possible as they're really just in the
  # way in the test suite.
  systemd.timers.fc-ceph-load-vm-images.enable = lib.mkForce false;
  systemd.timers.fc-ceph-mon-update-client-keys.enable = lib.mkForce false;
  systemd.timers.fc-ceph-clean-deleted-vms.enable = lib.mkForce false;
  systemd.timers.fc-ceph-purge-old-snapshots.enable = lib.mkForce false;
  systemd.timers.fc-ceph-rgw-users.enable = lib.mkForce false;

  flyingcircus.roles.ceph_osd.network = fclib.network.srv;

  # get rid of dependencies on sto/ stb network, the devhost does not have such interfaces
  systemd.services.fc-ceph-mon.wantedBy = lib.mkForce [ ];
  systemd.services.fc-ceph-mgr.wantedBy = lib.mkForce [ ];

  systemd.services.fc-ceph-mon.wants = lib.mkForce [ fclib.network.srv.addressUnit ];
  systemd.services.fc-ceph-mon.after = lib.mkForce [ fclib.network.srv.addressUnit ];
  systemd.services.fc-ceph-mgr.wants = lib.mkForce [ fclib.network.srv.addressUnit ];
  systemd.services.fc-ceph-mgr.after = lib.mkForce [ fclib.network.srv.addressUnit ];
  systemd.services.fc-ceph-osds-all.wants = lib.mkForce [ fclib.network.srv.addressUnit ];
  systemd.services.fc-ceph-osds-all.after = lib.mkForce [ fclib.network.srv.addressUnit ];
  systemd.services."fc-ceph-osd@".wants = lib.mkForce [ fclib.network.srv.addressUnit ];
  systemd.services."fc-ceph-osd@".after = lib.mkForce [ fclib.network.srv.addressUnit ];

  environment.shellAliases = {
    "init_cluster" = "/root/deployment/work/ceph/init_cluster.py";
  };

}
