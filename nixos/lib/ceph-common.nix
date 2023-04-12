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

  releasePkgs = {
    "jewel" = rec {
      ceph = pkgs.ceph-jewel;
      # temporary mapping until all actively used ceph releases are packaged in form of
      # the new schema with subpackages
      ceph-client = pkgs.ceph-jewel;
      libceph = pkgs.ceph-jewel;
      fcQemu = pkgs.fc.qemu-py2.override {
        ceph = libceph;
        qemu_ceph = qemu_ceph_versioned "jewel";
      };
      utilPhysical = pkgs.fc.util-physical.jewel.override {ceph = ceph-client;};
    };
    "luminous" = rec {
      ceph = pkgs.ceph-luminous;
      ceph-client = pkgs.ceph-luminous;
      libceph = pkgs.ceph-luminous;
      fcQemu = pkgs.fc.qemu-py2.override {
        ceph = libceph;
        qemu_ceph = qemu_ceph_versioned "luminous";
      };
      utilPhysical = pkgs.fc.util-physical.luminous.override {ceph = ceph-client;};
    };
    "nautilus" = rec {
      ceph = pkgs.ceph-nautilus.ceph;
      ceph-client = pkgs.ceph-nautilus.ceph-client;
      # both the C lib and the python modules
      libceph = pkgs.ceph-nautilus.libceph;
      fcQemu = pkgs.fc.qemu-py3.override {
        inherit libceph ceph;
        qemu_ceph = qemu_ceph_versioned "nautilus";
      };
      utilPhysical = pkgs.fc.util-physical.nautilus.override {ceph = ceph-client;};
    };
  };
  qemu_ceph_versioned = cephReleaseName: (pkgs.qemu_ceph.override {
     # Needs full ceph package, because
     #`libceph` is missing the dev output headers
     ceph = releasePkgs.${cephReleaseName}.ceph;
     });
in
rec {
  # constants
  inherit releasePkgs defaultRelease qemu_ceph_versioned;
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
  releaseAtLeast = targetRelease: currentRelease:
    let
    _releaseRecurser = rList: acc:
      if rList == [] then false   # exit condition 1
      # order matters here, do not consume the list head but only set to true and re-call
      else if (builtins.head rList == targetRelease && !acc) then _releaseRecurser rList true
      # this advances the list consumption but then also catches the case currentRelease == targetRelease
      else if builtins.head rList == currentRelease then acc  # exit condition 2
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
    releasePkgs.${cephPkg.codename}.utilPhysical # required for rbd-locktool
    pkgs.lz4  # required by image loading task
    ];


  # function that translates "camelCaseOptions" to "camel case options", credits to tilpner in #nixos@freenode
  expandCamelCase = lib.replaceStrings lib.upperChars (map (s: " ${s}") lib.lowerChars);
  expandCamelCaseAttrs = lib.mapAttrs' (name: value: lib.nameValuePair (expandCamelCase name) value);
  expandCamelCaseSection = lib.mapAttrs' (sectName: sectSettings: lib.nameValuePair sectName (expandCamelCaseAttrs sectSettings));
}
