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
  lldp-to-altname = callPackage ./lldp-to-altname {};
  logcheckhelper = callPackage ./logcheckhelper { };
  megacli = callPackage ./megacli { };
  multiping = callPackage ./multiping.nix {};

  qemu-nautilus = callPackage ./qemu rec {
    version = "1.4.3";
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      rev = version;
      hash = "sha256-1kMdHXjsxxIW0bEV6PfDeagdLVxZP87kPKm0Z4ZtXJA=";
    };
    qemu_ceph = pkgs.qemu-ceph-nautilus;
    ceph_client = pkgs.ceph-nautilus.ceph-client;
  };

  # Enable this temporarily during development, but DO NOT commit this as
  # it will break hydra and we can't cleanly filter it out of the automatic
  # test discovery at the moment.
  #
  # qemu-dev-nautilus = callPackage ./qemu {
  #   version = "dev";
  #   # builtins.toPath (testPath + "/.")
  #   src = ../../../fc.qemu/.;
  #   qemu_ceph = pkgs.qemu-ceph-nautilus;
  #   ceph_client = pkgs.ceph-nautilus.ceph-client;
  # };

  secure-erase = callPackage ./secure-erase {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = callPackage ./userscan.nix {};
  util-physical = callPackage ./util-physical {};
  telegraf-collect-psi = callPackage ./telegraf-collect-psi {};

}
