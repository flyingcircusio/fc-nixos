{ pkgs, pythonPackages, callPackage }:

rec {
  recurseForDerivations = true;

  agent = pythonPackages.callPackage ./agent {};
  agentWithSlurm = pythonPackages.callPackage ./agent { enableSlurm = true; };

  check-age = callPackage ./check-age {};
  # XXX: ceph is broken, needs integration of changes from 21.05
  # check-ceph = callPackage ./check-ceph {};
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-mongodb = callPackage ./check-mongodb {};
  check-postfix = callPackage ./check-postfix {};
  # XXX: ceph is broken, needs integration of changes from 21.05
  # ceph = callPackage ./ceph { inherit blockdev agent util-physical; };
  check-xfs-broken = callPackage ./check-xfs-broken {};
  blockdev = callPackage ./blockdev {};
  roundcube-chpasswd = callPackage ./roundcube-chpasswd {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  logcheckhelper = callPackage ./logcheckhelper { };
  # XXX: needs Python 2.7, untested on newer platform versions.
  # megacli = callPackage ./megacli { };
  multiping = callPackage ./multiping.nix {};
  secure-erase = callPackage ./secure-erase {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = callPackage ./userscan.nix {};
  # XXX: ceph is broken, needs integration of changes from 21.05
  # util-physical = callPackage ./util-physical {};
  telegraf-collect-psi = callPackage ./telegraf-collect-psi {};

}
