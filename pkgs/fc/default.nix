{
  pkgs,
  pyPackages,
  callPackage,
}:

rec {
  recurseForDerivations = true;

  agent = callPackage ./agent {
    nix = pkgs.nixVersions.nix_2_34;
    pyPackages = pyPackages;
  };
  agentWithSlurm = agent.override { enableSlurm = true; };

  blockdev = callPackage ./blockdev { };

  # fc-ceph does not need to be versioned on the Nix-package level as
  # it can be parametrized via config file for each individual subsystem.
  ceph = pyPackages.callPackage ./ceph {
    inherit agent blockdev;
  };

  check-age = callPackage ./check-age { };
  check-bgp-sessions = callPackage ./check-bgp-sessions { };
  check-haproxy = callPackage ./check-haproxy { };
  check-journal = callPackage ./check-journal.nix { };
  check-kvm-vrf-integrity = callPackage ./check-kvm-vrf-integrity { };
  check-link-redundancy = callPackage ./check-link-redundancy { };
  check-mongodb = pyPackages.callPackage ./check-mongodb { };
  check-postfix = callPackage ./check-postfix { };
  check-rib-integrity = callPackage ./check-rib-integrity { };
  check-skvaider = callPackage ./check-skvaider { };
  check-tls-cert = pyPackages.callPackage ./check-tls-cert { };
  check-vrf-default-routes = callPackage ./check-vrf-default-routes { };
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

  qemu-nautilus =
    (callPackage ./qemu rec {
      version = "1.7dev";
      src = pkgs.fetchFromGitHub {
        owner = "flyingcircusio";
        repo = "fc.qemu";
        # The release tooling didn't upgrade properly so we had to pick a specific
        # commit instead.
        rev = "256964f932353a4c5375d709445afecc8f48aaaf";
        hash = "sha256-ydEJlzio8ixFRqZEaDEwDkJFZYQ9RJ6DQhRJwTG+zik";
      };
      fc-ceph = ceph;
      qemu_ceph = pkgs.qemu-ceph-nautilus;
      ceph_client = pkgs.ceph-nautilus.ceph-client;
      python3Packages = pkgs.python311Packages;
    }).overridePythonAttrs
      (old: {
        propagatedBuildInputs = old.propagatedBuildInputs ++ [ pkgs.procps ];
      });

  qemu-pacific = callPackage ./qemu rec {
    version = "1.8dev";
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "fc.qemu";
      # The release tooling didn't upgrade properly so we had to pick a specific
      # commit instead.
      rev = "e4f467a3319217a1cefd99bdb416a58871c94a49";
      hash = "sha256-Z28I6VX5Gz2KXM0JcsHfxEDzNzlkt036C/5kDsZL9Cc=";
    };
    fc-ceph = ceph;
    qemu_ceph = pkgs.qemu-ceph-pacific;
    ceph_client = pkgs.ceph-pacific.ceph-client;
    python3Packages = pkgs.python313Packages;
  };

  # Enable this temporarily during development, but DO NOT commit this as
  # it will break hydra and we can't cleanly filter it out of the automatic
  # test discovery at the moment.
  #
  # qemu-dev-pacific = qemu-pacific.overrideAttrs (old: {
  #   # for tests and development checkouts on kvm hosts:
  #   src = ../../../fc.qemu/.;
  #   # for nix-shell . -A fc.qemu-dev-pacific
  #   # src = ../../../fc.qemu/.;
  # });

  roundcube-chpasswd = callPackage ./roundcube-chpasswd { };
  roundcube-chpasswd-py = callPackage ./roundcube-chpasswd-py { };
  secure-erase = callPackage ./secure-erase { };
  sensuplugins = callPackage ./sensuplugins { };
  sensusyntax = callPackage ./sensusyntax { };
  skvaider = callPackage ./skvaider { };
  telegraf-collect-psi = callPackage ./telegraf-collect-psi { };
  telegraf-routes-summary = callPackage ./telegraf-routes-summary { };
  trafficclient = pyPackages.callPackage ./trafficclient.nix { };
  userscan = callPackage ./userscan.nix { };
  util-physical = callPackage ./util-physical { };
}
