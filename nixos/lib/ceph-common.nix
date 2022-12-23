# common value constants and functions used by several ceph roles
{ lib, pkgs }:

with lib;
let
  # supported ceph release codenames, from newest to oldest
  # TODO: Once all ceph packages have a similar structure, releasePkgs can be
  # generated from this ist
  releaseOrder = [ "nautilus" "luminous" "jewel"];
  cephReleaseType = types.enum (builtins.attrNames releasePkgs);
  defaultRelease = "luminous";

  # ====== mapping of packages per ceph release =======
  # FIXME: possible change structure from <package>.<cephRelease> to <ceph

  releasePkgs = {
    "jewel" = pkgs.ceph-jewel;
    "luminous" = pkgs.ceph-luminous;
    "nautilus" = pkgs.ceph-nautilus.ceph;
  };
  # temporary map until all actively used ceph releases are packaged in form of the new
  # schema with subpackages
  clientPkgs = {
    "jewel" = pkgs.ceph-jewel;
    "luminous" = pkgs.ceph-luminous;
    "nautilus" = pkgs.ceph-nautilus.ceph-client;
  };
  qemu_ceph_versioned = cephReleaseName: (pkgs.qemu_ceph.override {
     ceph = releasePkgs.${cephReleaseName};
     });
  # both the C liab and the python modules
  libcephPkgs = {
    "jewel" = pkgs.ceph-jewel;
    "luminous" = pkgs.ceph-luminous;
    "nautilus" = pkgs.ceph-nautilus.libceph;
  };
  fcQemuPkgs = {
    jewel = pkgs.fc.qemu-py2.override {
      ceph = libcephPkgs.jewel;
      qemu_ceph = qemu_ceph_versioned "jewel";
    };
    luminous = pkgs.fc.qemu-py2.override {
      ceph = libcephPkgs.luminous;
      qemu_ceph = qemu_ceph_versioned "luminous";
    };
    nautilus = pkgs.fc.qemu-py3.override {
      libceph = libcephPkgs.nautilus;
      qemu_ceph = qemu_ceph_versioned "nautilus";
    };
  };
  utilPhysicalPkgs = {
    "jewel" = pkgs.fc.util-physical.jewel.override {ceph = clientPkgs.jewel;};
    "luminous" = pkgs.fc.util-physical.luminous.override {ceph = clientPkgs.luminous;};
    "nautilus" = pkgs.fc.util-physical.nautilus.override {ceph = clientPkgs.nautilus;};
  };
in
rec {
  # constants
  inherit releasePkgs clientPkgs fcQemuPkgs libcephPkgs utilPhysicalPkgs defaultRelease qemu_ceph_versioned;
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
    utilPhysicalPkgs.${cephPkg.codename} # required for rbd-locktool
    pkgs.lz4  # required by image loading task
    ];


  # function that translates "camelCaseOptions" to "camel case options", credits to tilpner in #nixos@freenode
  expandCamelCase = lib.replaceStrings lib.upperChars (map (s: " ${s}") lib.lowerChars);
  expandCamelCaseAttrs = lib.mapAttrs' (name: value: lib.nameValuePair (expandCamelCase name) value);
  expandCamelCaseSection = lib.mapAttrs' (sectName: sectSettings: lib.nameValuePair sectName (expandCamelCaseAttrs sectSettings));
}
