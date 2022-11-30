{ pkgs, callPackage }:

rec {
  recurseForDerivations = true;

  agent = callPackage ./agent {};

  check-age = callPackage ./check-age {};
  check-ceph = {
    jewel = callPackage ./check-ceph/jewel {ceph = pkgs.ceph-jewel;};
    luminous = callPackage ./check-ceph/luminous {ceph = pkgs.ceph-luminous;};
  };
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-mongodb = callPackage ./check-mongodb {};
  check-postfix = callPackage ./check-postfix {};
  ceph = callPackage ./ceph { inherit blockdev agent util-physical; };
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

  qemu = callPackage ./qemu {
      version = "1.2-dev";
      src = pkgs.fetchFromGitHub {
        owner = "flyingcircusio";
        repo = "fc.qemu";
        rev = "efbd2df73e236fa8a799c3ab5cdfbe7ecb561c8e";
        hash = "sha256-gcfZ113kI3aeyH55gzVlROiVcZI1ZlGHYboCN2eIte4";
      };
  };

  secure-erase = callPackage ./secure-erase {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = callPackage ./userscan.nix {};
  util-physical = callPackage ./util-physical {};
  telegraf-collect-psi = callPackage ./telegraf-collect-psi {};

}
