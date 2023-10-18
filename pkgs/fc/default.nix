{ pkgs, pythonPackages, callPackage }:

rec {
  recurseForDerivations = true;

  agent = pythonPackages.callPackage ./agent {};

  check-age = callPackage ./check-age {};
  check-ceph = {
    nautilus = callPackage ./check-ceph/nautilus {inherit (pkgs.ceph-nautilus) ceph-client;};
  };
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-mongodb = callPackage ./check-mongodb {};
  check-postfix = callPackage ./check-postfix {};

  # fc-ceph still has a transitive dependency on the `ceph` package due to util-physical,
  # so it needs to be parameterised depending on the release
  cephWith = cephPkg:
    pythonPackages.callPackage ./ceph {
      inherit blockdev agent;
      util-physical = util-physical.${cephPkg.codename}.override {ceph = cephPkg;};
    };
  # normally, fc-ceph is installed via a role, but here are some direct installable
  # packages in case they're needed:
  ceph = {
    cephWithNautilus = cephWith pkgs.ceph-nautilus.ceph-client;
  };

  check-xfs-broken = callPackage ./check-xfs-broken {};
  blockdev = callPackage ./blockdev {};
  collectdproxy = callPackage ./collectdproxy {};
  roundcube-chpasswd = callPackage ./roundcube-chpasswd {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  ledtool = pkgs.writers.writePython3Bin "fc-ledtool"
    {} (builtins.readFile ./ledtool/led.py);
  logcheckhelper = callPackage ./logcheckhelper { };
  megacli = callPackage ./megacli { };
  multiping = callPackage ./multiping.nix {};

  qemu = callPackage ./qemu rec {
    version = "1.3.1";
    # src = /path/to/fc.qemu/checkout ; # development
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      rev = version;
      hash = "sha256-eTJxhdSelMJ8UFE8mtgntFVgY/+Ne2K4niH5X9JP9Tc=";
    };
  };

  secure-erase = callPackage ./secure-erase {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = callPackage ./userscan.nix {};
  util-physical = {
    nautilus = callPackage ./util-physical/ceph-nautilus {ceph = pkgs.ceph-nautilus.ceph-client;};
  };
  telegraf-collect-psi = callPackage ./telegraf-collect-psi {};

}
