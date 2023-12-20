# common value constants and functions used by several ceph roles
{ lib, pkgs }:

with lib;
let
  # supported ceph release codenames, from newest to oldest
  # TODO: Once all ceph packages have a similar structure, those can be
  # generated from this list (let's wait for pacific to see if the structure holds)
  releaseOrder = [ "nautilus" ];
  cephReleaseType = types.enum releaseOrder;
  defaultRelease = "nautilus";
in
rec {
  # constants
  inherit defaultRelease;
  releaseOption = lib.mkOption {
    type = cephReleaseType;
    # centrally manage the default release for all roles here
    default = defaultRelease;
  };

  mkPkgs = release: rec {
    ceph = pkgs."ceph-${release}".ceph;
    ceph-client = pkgs."ceph-${release}".ceph-client;
    libceph = pkgs."ceph-${release}".libceph;

    fc-ceph = pkgs.fc.ceph;
    fc-ceph-path = lib.makeBinPath [
      ceph
      ceph-client
      pkgs.xfsprogs
      pkgs.lvm2
      pkgs.util-linux
      pkgs.systemd
      pkgs.gptfdisk
      pkgs.coreutils
      pkgs.lz4  # required by image loading task
      pkgs.cryptsetup  # full-disk encryption
    ];

    fc-check-ceph = pkgs.fc."check-ceph-${release}";

    fc-qemu = pkgs.fc."qemu-${release}";
    qemu = pkgs."qemu-ceph-${release}";
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

  # function that translates "camelCaseOptions" to "camel case options", credits to tilpner in #nixos@freenode
  expandCamelCase = lib.replaceStrings lib.upperChars (map (s: " ${s}") lib.lowerChars);
  expandCamelCaseAttrs = lib.mapAttrs' (name: value: lib.nameValuePair (expandCamelCase name) value);
  expandCamelCaseSection = lib.mapAttrs' (sectName: sectSettings: lib.nameValuePair sectName (expandCamelCaseAttrs sectSettings));
}
