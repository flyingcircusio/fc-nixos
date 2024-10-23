{ pkgs, pythonPackages, callPackage }:

rec {
  recurseForDerivations = true;

  agent = pythonPackages.callPackage ./agent {};

  blockdev = callPackage ./blockdev {};

  # fc-ceph does not need to be versioned on the Nix-package level as
  # it can be parametrized via config file for each individual subsystem.
  ceph = pythonPackages.callPackage ./ceph {
    inherit agent blockdev;
    py_pytest_patterns = pkgs.py_pytest_patterns.override {python3Packages = pythonPackages;};
  };

  check-age = callPackage ./check-age {};
  check-ceph-nautilus = callPackage ./check-ceph/nautilus {inherit (pkgs.ceph-nautilus) ceph-client;};
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-link-redundancy = callPackage ./check-link-redundancy {};
  check-mongodb = callPackage ./check-mongodb {};
  check-postfix = callPackage ./check-postfix {};
  check-rib-integrity = callPackage ./check-rib-integrity {};

  check-xfs-broken = callPackage ./check-xfs-broken {};
  collectdproxy = callPackage ./collectdproxy {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  ipmitool = callPackage ./ipmitool {};
  install = callPackage ./install {};

  ledtool = pkgs.writers.writePython3Bin "fc-ledtool"
    {} (builtins.readFile ./ledtool/led.py);
  lldp-to-altname = callPackage ./lldp-to-altname {};
  logcheckhelper = callPackage ./logcheckhelper { };
  megacli = callPackage ./megacli { };
  multiping = callPackage ./multiping.nix {};
  neighbour-cache-monitor = callPackage ./neighbour-cache-monitor {};
  ping-on-tap = callPackage ./ping-on-tap {};
  qemu-nautilus = callPackage ./qemu rec {
    version = "1.6";
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      rev = version;
      hash = "sha256-oxV29okkTqkNm5HvwrwWS+hABcH7cd70mL83f72SLsQ=";
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
  #   src = ../../../../../fc.qemu/.;
  #   qemu_ceph = pkgs.qemu-ceph-nautilus;
  #   ceph_client = pkgs.ceph-nautilus.ceph-client;
  # };

  roundcube-chpasswd = callPackage ./roundcube-chpasswd {};
  secure-erase = callPackage ./secure-erase {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  telegraf-collect-psi = callPackage ./telegraf-collect-psi {};
  telegraf-routes-summary = callPackage ./telegraf-routes-summary {};
  trafficclient = pythonPackages.callPackage ./trafficclient.nix {};
  userscan = callPackage ./userscan.nix {};
  util-physical = callPackage ./util-physical {};

}
