{ pkgs, pythonPackages, callPackage }:

rec {
  recurseForDerivations = true;

  agent = pythonPackages.callPackage ./agent {};

  check-age = callPackage ./check-age {};
  check-ceph-nautilus = callPackage ./check-ceph/nautilus {inherit (pkgs.ceph-nautilus) ceph-client;};
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-mongodb = callPackage ./check-mongodb {};
  check-postfix = callPackage ./check-postfix {};

  # fc-ceph does not need to be versioned on the Nix-package level as
  # it can be parametrized via config file for each individual subsystem.
  ceph = pythonPackages.callPackage ./ceph {
    inherit agent blockdev;
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

  qemu-nautilus = callPackage ./qemu rec {
    version = "1.3.1";
    # src = /path/to/fc.qemu/checkout ; # development
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      rev = version;
      hash = "sha256-eTJxhdSelMJ8UFE8mtgntFVgY/+Ne2K4niH5X9JP9Tc=";
    };
    qemu_ceph = pkgs.qemu-ceph-nautilus;
  };
  qemu-dev-nautilus = callPackage ./qemu {
    version = "dev";
    # builtins.toPath (testPath + "/.")
    src = ../../../../../fc.qemu/.;
    qemu_ceph = pkgs.qemu-ceph-nautilus;
  };

  secure-erase = callPackage ./secure-erase {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = callPackage ./userscan.nix {};
  util-physical = callPackage ./util-physical {};
  telegraf-collect-psi = callPackage ./telegraf-collect-psi {};

}
