{ pkgs, callPackage }:

rec {
  recurseForDerivations = true;

  agent = callPackage ./agent {};

  check-age = callPackage ./check-age {};
  check-ceph = {
    jewel = callPackage ./check-ceph/jewel {ceph = pkgs.ceph-jewel;};
    luminous = callPackage ./check-ceph/luminous {ceph = pkgs.ceph-luminous;};
    # nautilus needs no changes from the luminous version
    nautilus = callPackage ./check-ceph/luminous {ceph = pkgs.ceph-nautilus.ceph-client;};
  };
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-mongodb = callPackage ./check-mongodb {};
  check-postfix = callPackage ./check-postfix {};

  # fc-ceph still has a transitive dependency on the `ceph` package due to util-physical,
  # so it needs to be parameterised depending on the release
  cephWith = cephPkg:
    callPackage ./ceph {
      inherit blockdev agent;
      util-physical = util-physical.${cephPkg.codename}.override {ceph = cephPkg;};
    };
  # normally, fc-ceph is installed via a role, but here are some direct installable
  # packages in case they're needed:
  ceph = {
    jewel = cephWith pkgs.ceph-jewel;
    luminous = cephWith pkgs.ceph-luminous;
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

  qemu-py2 = callPackage ./qemu/py2.nix {
      version = "1.2-dev";
      src = pkgs.fetchFromGitHub {
        owner = "flyingcircusio";
        repo = "fc.qemu";
        rev = "bcf373c57a39bb373f45022cae4015221e9aa94f";
        hash = "sha256-4rIwMzsYYvKGGybkFFu3z0D/RD8LXIJP5GG0oB9lxpc";
      };
  };
  qemu-py3 = callPackage ./qemu/py3.nix rec {
    version = "1.3.1";
    # src = /path/to/fc.qemu/checkout ; # development
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      rev = version;
      hash = "sha256-eTJxhdSelMJ8UFE8mtgntFVgY/+Ne2K4niH5X9JP9Tc=";
    };
    libceph = pkgs.ceph-nautilus.libceph;
  };

  secure-erase = callPackage ./secure-erase {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = callPackage ./userscan.nix {};
  util-physical = {
    # luminous code is compatible to jewel
    jewel = callPackage ./util-physical/ceph-luminous {ceph = pkgs.ceph-jewel;};
    luminous = callPackage ./util-physical/ceph-luminous {ceph = pkgs.ceph-luminous;};
    nautilus = callPackage ./util-physical/ceph-nautilus {ceph = pkgs.ceph-nautilus.ceph-client;};
  };
  telegraf-collect-psi = callPackage ./telegraf-collect-psi {};

}
