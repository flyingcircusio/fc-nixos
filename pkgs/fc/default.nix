{
  pkgs,
  pyPackages,
  callPackage,
}:

rec {
  recurseForDerivations = true;

  agent = callPackage ./agent {
    nix = pkgs.nixVersions.nix_2_28;
    pyPackages = pyPackages;
  };
  agentWithSlurm = (agent.override { enableSlurm = true; }).overrideAttrs (oA: {
    # FIXME: PL-133856 pyslurm incompatible with slurm 25.05
    meta = oA.meta // {
      broken = true;
    };
  });

  blockdev = callPackage ./blockdev { };

  # fc-ceph does not need to be versioned on the Nix-package level as
  # it can be parametrized via config file for each individual subsystem.
  ceph = pyPackages.callPackage ./ceph {
    inherit agent blockdev;
  };

  check-age = callPackage ./check-age { };
  check-ceph-nautilus = callPackage ./check-ceph/nautilus {
    inherit (pkgs.ceph-nautilus) ceph-client;
    python3Packages = pkgs.python38Packages;
  };
  check-haproxy = callPackage ./check-haproxy { };
  check-journal = callPackage ./check-journal.nix { };
  check-link-redundancy = callPackage ./check-link-redundancy { };
  check-mongodb = pyPackages.callPackage ./check-mongodb { };
  check-postfix = callPackage ./check-postfix { };
  check-rib-integrity = callPackage ./check-rib-integrity { };
  check-xfs-broken = callPackage ./check-xfs-broken { };

  fix-so-rpath = callPackage ./fix-so-rpath { };
  ipmitool = callPackage ./ipmitool { };
  install = callPackage ./install { };

  ledtool = pkgs.writers.writePython3Bin "fc-ledtool" { } (builtins.readFile ./ledtool/led.py);
  lldp-to-altname = callPackage ./lldp-to-altname { };
  logcheckhelper = callPackage ./logcheckhelper { };
  megacli = callPackage ./megacli { };
  multiping = callPackage ./multiping.nix { };
  neighbour-cache-monitor = callPackage ./neighbour-cache-monitor { };
  ping-on-tap = callPackage ./ping-on-tap { };

  qemu-nautilus = callPackage ./qemu rec {
    version = "1.7dev";
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      # The release tooling didn't upgrade properly so we had to pick a specific
      # commit instead.
      rev = "44a7dbba681f9c2a0418397ca15aef68cbba7071";
      hash = "sha256-hUzhaLUrK6Sp+d0o/8a3UZkvv+ZiAr1JS60hd/X6epM=";
    };
    fc-ceph = ceph;
    qemu_ceph = pkgs.qemu-ceph-nautilus;
    ceph_client = pkgs.ceph-nautilus.ceph-client;
    python3Packages = pkgs.python311Packages;
  };

  # Enable this temporarily during development, but DO NOT commit this as
  # it will break hydra and we can't cleanly filter it out of the automatic
  # test discovery at the moment.
  #
  # qemu-dev-nautilus = qemu-nautilus.overrideAttrs (old: {
  #   # for tests and development checkouts on kvm hosts:
  #   src = ../../../../../fc.qemu/.;
  #   # for nix-shell . -A fc.qemu-dev-nautilus
  #   # src = ../../../fc.qemu/.;
  # });

  roundcube-chpasswd = callPackage ./roundcube-chpasswd { };
  roundcube-chpasswd-py = callPackage ./roundcube-chpasswd-py { };
  secure-erase = callPackage ./secure-erase { };
  sensuplugins = callPackage ./sensuplugins { };
  sensusyntax = callPackage ./sensusyntax { };
  telegraf-collect-psi = callPackage ./telegraf-collect-psi { };
  telegraf-routes-summary = callPackage ./telegraf-routes-summary { };
  trafficclient = pyPackages.callPackage ./trafficclient.nix { };
  userscan = callPackage ./userscan.nix { };
  util-physical = callPackage ./util-physical { };
}
