# common value constants and functions used by several ceph roles
{ lib, pkgs }:

with lib;
let
  releasePkgs = {
    "jewel" = pkgs.ceph-jewel;
    "luminous" = pkgs.ceph-luminous;
  };
  cephReleaseType = types.enum (builtins.attrNames releasePkgs);
  defaultRelease = "jewel";
in
{
  # constants
  inherit releasePkgs defaultRelease;
  releaseOption = lib.mkOption {
    type = cephReleaseType;
    # centrally manage the default release for all roles here
    default = defaultRelease;
  };

  # helper functions

  # returns the luminous ceph package if at least one active role is on
  # luminous already, otherwise jewel.
  # upgrade notes: needs to be adjusted at next ceph release upgrade (mimic)
  highestCephReleaseType = cephReleaseType // {
    merge = _: vals: if (any (r: r.value == "luminous") vals) then "luminous" else "jewel";
  };

  # return a suitable binary path for fc-ceph, parameterised with the desired ceph package
  fc-ceph-path = cephPkg: lib.makeBinPath [
    cephPkg
    pkgs.xfsprogs
    pkgs.lvm2
    pkgs.util-linux
    pkgs.systemd
    pkgs.gptfdisk
    pkgs.coreutils
    (pkgs.fc.util-physical.override {ceph = cephPkg;}) # required for rbd-locktool
    pkgs.lz4  # required by image loading task
    ];
}
