# common value constants and functions used by several ceph roles
{ lib, pkgs }:

with lib;
let
  # supported ceph release codenames, from newest to oldest
  # TODO: Once all ceph packages have a similar structure, releasePkgs can be
  # generated from this ist
  releaseOrder = [ "nautilus" "luminous" "jewel"];
  releasePkgs = {
    "jewel" = pkgs.ceph-jewel;
    "luminous" = pkgs.ceph-luminous;
    "nautilus" = pkgs.ceph-nautilus.ceph;
  };
  # temporary map until all actively used ceph releases are packaged in form of the new
  # schema with subpackages
  clientPackages = {
    "jewel" = pkgs.ceph-jewel;
    "luminous" = pkgs.ceph-luminous;
    "nautilus" = pkgs.ceph-nautilus.ceph-client;
  };
  cephReleaseType = types.enum (builtins.attrNames releasePkgs);
  defaultRelease = "luminous";
in
{
  # constants
  inherit releasePkgs clientPkgs defaultRelease;
  releaseOption = lib.mkOption {
    type = cephReleaseType;
    # centrally manage the default release for all roles here
    default = defaultRelease;
  };

  # helper functions

  # returns the highest supported release encountered in any of the active roles
  # utilising that option type
  highestCephReleaseType = cephReleaseType // {
    merge = let
      # test the elements of a precedence list from start to end, one by one, whether
      # that element appears in `vals`, if yes return that.
      selectFirst = precedenceList: vals:
        if precedenceList == [] then abort "Unsupported ceph release"
        else (if (builtins.any (r: r == builtins.head precedenceList) vals)
          then builtins.head precedenceList
          # recursion step
          else selectFirst (builtins.tail precedenceList) vals);
    in _: definitionAttrs: selectFirst releaseOrder (builtins.catAttrs "value" definitionAttrs);
  };
  # returns true if the provided current release is the target release or newer
  # FIXME: could this be done as a fold?
  releaseAtLeast = targetRelease: currentRelease:
    let
    _releaseRecurser = rList: acc:
      if rList == [] then false
      # order matters here, do not consume the list head but only set to true and re-call
      else if (builtins.head rList == targetRelease && !acc) then _releaseRecurser rList true
      # this advances the list consumption but then also catches the case currentRelease == targetRelease
      else if builtins.head rList == currentRelease then acc
      else _releaseRecurser (builtins.tail rList) acc;
    in _releaseRecurser (lib.reverseList releaseOrder) false;


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
