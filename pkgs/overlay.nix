self: super:
let
  poetry2nixSrc = (import ../release/versions.nix { pkgs = super; }).poetry2nix;
  poetry2nix = import poetry2nixSrc { pkgs = self; };

  # import fossar/nix-phps overlay with nixpkgs-unstable's generic.nix copied in
  # then use release-set as pkgs
  phps = (import ../nix-phps/pkgs/phps.nix) (../nix-phps) { } super;

  nixpkgs-21_05-src = fetchFromGitHub {
    hash = "sha256-useJKcX1iIrhJFP6zMUx8ALS1HxJRYgk/tkKhLHkL5E=";
    owner = "flyingcircusio";
    repo = "nixpkgs";
    rev = "1710b09739d84b3038f92897ad5f7c117114c71d";
  };

  nixpkgs-ceph-pacific =
    # we build ceph pacific from a nixpkgs-23.11 branch which also holds
    # a few additional modifications and updates to the original upstream packaging
    import
      (fetchFromGitHub {
        hash = "sha256-RIo+rVVGk7/vD8QXyDJ0hQSWzU1sET1KdRiwVEm+GG0=";
        owner = "flyingcircusio";
        repo = "nixpkgs";
        rev = "38815aab5fa9d1ab6f2e9d9f2929a49a7feef41a";
        # branch = "fc-ceph-pacific"
      })
      {
        inherit (self) config;
      };

  fc-nixos-21_05-src = fetchFromGitHub {
    hash = "sha256-U1ZpdP31bpWCParWr79YWVpA+oIU12cRkI2gf2l+IBM=";
    owner = "flyingcircusio";
    repo = "fc-nixos";
    rev = "407b9df6395bd7098aa4e1b4e3f70ee94e41948e";
  };
  fc-nixos-21_05 = builtins.trace "using fc-nixos-21.05" (
    import fc-nixos-21_05-src {
      inherit (self) config;
      nixpkgs = nixpkgs-21_05-src;
    }
  );

  inherit (super)
    fetchpatch
    fetchFromGitHub
    fetchurl
    lib
    ;
  inherit (builtins) hasAttr storePath;

  getClosureFromStore =
    path:
    if hasAttr "fetchClosure" builtins then
      builtins.fetchClosure {
        fromStore = "https://s3.whq.fcio.net/hydra";
        fromPath = path;
        inputAddressed = true;
      }
    else
      storePath path;

  phpLogPermissionPatch = fetchpatch {
    url = "https://github.com/flyingcircusio/php-src/commit/f3a22e2ed6e461d8c3fac84c2fd2c9e441c9e4d4.patch";
    hash = "sha256-ttHjEOGJomjs10PRtM2C6OLX9LCvboxyDSKdZZHanFQ=";
  };
  # we need to use overrideAttrs, as the `extraPatches` function argument of the generic PHP builder is
  # redefined and replaced by the specific version builder.
  patchPhps =
    patch: phpPkg:
    phpPkg.overrideAttrs (prev: {
      patches = (prev.patches or [ ]) ++ (prev.extraPatches or [ ]) ++ [ patch ];
    });
in
builtins.mapAttrs (_: patchPhps phpLogPermissionPatch) {
  #
  # == we need to patch upstream PHP for more liberal fpm log file permissions
  #

  # Import old php versions from nix-phps.
  inherit (phps)
    php72
    php73
    php74
    php80
    php81
    ;
  # Import NixOS upstream PHPs.
  inherit (super)
    php82
    php83
    php84
    ;

}
//
  builtins.mapAttrs
    (
      _:
      patchPhps (fetchpatch {
        url = "https://github.com/flyingcircusio/php-src/commit/1a7e4834d94d72564521fffd6ceec5a378693cb7.patch";
        hash = "sha256-MWZdXUsvkpxhC9VVttrINY2E4X+PD7lChgkL3VYlk10=";
      })
    )
    {
      inherit (super) php83 php84;
    }
//
  builtins.mapAttrs
    (
      _:
      patchPhps (fetchpatch {
        url = "https://github.com/flyingcircusio/php-src/commit/7f5f62ff1bedc46df43d048920a3bc80bef22500.diff?full_index=1";
        hash = "sha256-yInMJrzlNZsqnePv7aesDdZYOynCWs+d7FrYNQ5Teug=";
      })
    )
    {
      inherit (super) php85;
    }
// {
  pythonPackagesExtensions = super.pythonPackagesExtensions ++ [
    (python-self: python-super: {
      pytest_patterns = python-self.callPackage ./python/pytest-patterns { };
      pymongo3 = python-super.pymongo.overridePythonAttrs (old: {
        version = "3.13.0";
        src = python-self.fetchPypi {
          inherit (old) pname;
          version = "3.13.0";
          hash = "sha256-4i1s9YAs0JtnTDB8yeA4cLjDfFA+vsPSW4byzoxTXcc=";
        };
      });
      pymongo4_13 = python-super.pymongo.overridePythonAttrs (old: {
        version = "4.13.2";
        src = python-self.fetchPypi {
          inherit (old) pname;
          version = "4.13.2";
          hash = "sha256-D2TGRpwjYpYubOlyWK4Tkau6FWapU6SSVi0pJLRIFcI=";
        };
      });
    })
  ];

  pyproject-nix =
    import
      (super.fetchFromGitHub {
        owner = "pyproject-nix";
        repo = "pyproject.nix";
        rev = "794afa6eb588b498344f2eaa36ab1ceb7e6b0b09";
        hash = "sha256-wTfdyzzrmpuqt4TQQNqilF91v0m5Mh1stNy9h7a/WK4=";
      })
      {
        inherit (self) lib;
      };
  uv2nix =
    import
      (super.fetchFromGitHub {
        owner = "pyproject-nix";
        repo = "uv2nix";
        rev = "5d0e883867b1cf53263fcf1bfd34542d40abf5a9";
        hash = "sha256-dMTjy8hu4XFAdNHdcLtCryN3SHqSUFHHqDLep+3b2v4=";
      })
      {
        inherit (self) lib pyproject-nix;
      };
  pyproject-build-systems =
    import
      (super.fetchFromGitHub {
        owner = "pyproject-nix";
        repo = "build-system-pkgs";
        rev = "b6e74f433b02fa4b8a7965ee24680f4867e2926f";
        hash = "sha256-ZoTdqZP03DcdoyxvpFHCAek4bkPUTUPUF3oCCgc3dP4=";
      })
      {
        inherit (self) lib uv2nix pyproject-nix;
      };

  #
  # == our own stuff
  #
  fc = (
    import ./default.nix {
      pkgs = self;
      # Only used by the agent for now but we should probably use this
      # for all our Python packages and update Python in sync then.
      pyPackages = self.python312Packages;
    }
  );

  backy = self.callPackage ./backy { };

  #
  # imports from other nixpkgs versions or local definitions
  #

  apacheHttpdLegacyCrypt = self.apacheHttpd.override {
    aprutil = self.aprutil.override { libxcrypt = self.libxcrypt-legacy; };
  };

  # Sidecar bird for managing VRF routes on routers
  bird2-vrf = self.bird2.overrideAttrs (old: {
    configureFlags = [
      "--localstatedir=/var"
      "--runstatedir=/run/bird-vrf"
    ];

    # Bird will not import routes in the kernel which are tagged with
    # the "proto bird" flag, as these are considered bird's own
    # routes. So let's change the VRF Bird's idea of what its "own"
    # routes are so it can interoperate with the main Bird instance.
    postPatch = ''
      echo Updating native route protocol flag
      ${self.gnused}/bin/sed -i -E -e 's/RTPROT_BIRD/201/g' sysdep/linux/netlink.c
    '';

    postInstall = ''
      for prog in bird birdc birdcl; do
          mv $out/sbin/$prog $out/sbin/vrf-$prog
      done
    '';
  });

  busybox = super.busybox.overrideAttrs (oldAttrs: {
    meta.priority = 10;
  });

  check_ipmi_sensor = super.callPackage ./check_ipmi_sensor.nix { };
  check_md_raid = super.callPackage ./check_md_raid { };
  check_megaraid = super.callPackage ./check_megaraid { };

  # default ceph packages
  inherit (self.ceph-nautilus) ceph ceph-client libceph;
  # upstream ceph packaging switched to offering a reduced client tooling set, let's see how that works
  ceph-nautilus = lib.dontRecurseIntoAttrs fc-nixos-21_05.ceph-nautilus;
  ceph-pacific =
    let
      applyBaselinePatches =
        cephPkg:
        cephPkg.overrideAttrs (oldAttrs: {
          patches = (oldAttrs.patches or [ ]) ++ [
            ./ceph/pacific/rgw-reduce-log-verbosity.patch
            ./ceph/pacific/rbd-migration-status-poolname.patch
          ];
        });
      patchedCeph = builtins.mapAttrs (_: applyBaselinePatches) {
        inherit (nixpkgs-ceph-pacific) ceph ceph-client;
      };
    in
    rec {
      inherit (patchedCeph) ceph ceph-client;
      # XXX: ceph-client for now also contains *our* rbd-locktool executable.
      # We should reconsider this once we are able to use ceph from the current nixpkgs.
      libceph = ceph.lib;
    };

  consul = builtins.trace "using 21.05 consul" (
    fc-nixos-21_05.consul.overrideAttrs (old: {
      meta.mainProgram = "consul";
    })
  );

  docsplit = super.callPackage ./docsplit { };

  discourseWithNixosPlugins = super.discourse.override {
    plugins = (
      with super.discourse.plugins;
      [
        discourse-bbcode-color
        discourse-docs
        discourse-events
        discourse-prometheus
        discourse-saved-searches
        discourse-yearly-review
      ]
    );
  };

  dool = super.dool.overrideAttrs (old: {
    patches = old.patches or [ ] ++ [ ./dool-interface-altnames.patch ];
  });

  frr = super.frr.overrideAttrs (old: rec {
    version = "10.4.2";
    src = super.fetchFromGitHub {
      owner = "FRRouting";
      repo = old.pname;
      rev = "${old.pname}-${version}";
      hash = "sha256-cWb3bCmHYUrDw2Xa5eVBaAlTLbm8o0FiFD5dA+G4kso=";
    };

    patches = [
      ./frr/0001-Don-t-throw-error-when-log-directory-already-exists.patch
      ./frr/0002-zebra-dplane-sleep-after-writing-batches-to-netlink.patch
      ./frr/0003-netlink-don-t-manage-kernel-neighbour-table-entries-.patch
    ];
  });

  go-audit = super.go-audit.overrideAttrs (
    goSelf: goSuper: {
      patches = [
        ./go-audit/0001-Split-audit-message-into-key-value-pairs-for-better-.patch
        ./go-audit/0002-Decode-audit-message-type-number-into-string-constan.patch
        ./go-audit/0003-Disaggregate-audit-events-into-separate-log-entries.patch
        ./go-audit/0004-Provide-a-human-readable-decoded-view-for-selected-a.patch
      ];
    }
  );

  innotop = super.callPackage ./percona/innotop.nix { };

  ipmitool = super.ipmitool.overrideAttrs (
    a:
    a
    // {
      buildInputs = a.buildInputs ++ [
        super.ncurses
        super.readline
      ];
    }
  );

  # TODO: re-evaluate whether this still needs to be vendored without lmdb support (#PL-130446)
  libmodsecurity = super.callPackage ./libmodsecurity { };

  # Change this alias for trying out other kernel packages on non-production
  # machines.
  # The logic for enabling different kernels on prod and non-prod remains active
  # the whole time. But in the normal case, both kernels point to the same
  # stable kernel packages.
  linuxKernelVerify = self.linux_6_18;

  linuxKernelStable = self.linux_6_12;

  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };
  kubernetes-dashboard-metrics-scraper =
    super.callPackage ./kubernetes-dashboard-metrics-scraper.nix
      { };

  auditbeat7-oss = self.auditbeat7.overrideAttrs (
    a:
    a
    // {
      name = "auditbeat-oss-${a.version}";
      # XXX: tests break without x-pack (bad!)
      # preBuild = "rm -rf x-pack";
    }
  );

  cyrus_sasl-legacyCrypt = super.cyrus_sasl.override {
    libxcrypt = self.libxcrypt-legacy;
  };

  dovecot =
    (super.dovecot.override {
      cyrus_sasl = self.cyrus_sasl-legacyCrypt;
    }).overrideAttrs
      (old: {
        strictDeps = true;
        buildInputs = [ self.libxcrypt-legacy ] ++ old.buildInputs;
      });

  elasticsearch6-oss = (
    lib.toDerivation (
      getClosureFromStore /nix/store/gkw63x51dmnyr7v66vf713ni7b8i3z37-elasticsearch-oss-6.8.21
    )
    // {
      version = "6.8.21";
    }
  );

  filebeat7-oss = self.filebeat7.overrideAttrs (
    a:
    a
    // {
      name = "filebeat-oss-${a.version}";
      # XXX: tests break without x-pack (bad!)
      # preBuild = "rm -rf x-pack";
    }
  );

  gptfdisk = super.gptfdisk.overrideAttrs (
    a:
    a
    // {
      patches = a.patches or [ ] ++ [
        ./gptfdisk-dont-sleep.patch
      ];
    }
  );

  graylogFrozen = (
    lib.toDerivation (getClosureFromStore /nix/store/yj365yr01p6yp2axj943b4l8ngzzxvkw-graylog-3.3.16)
    // {
      version = "3.3.16";
    }
  );

  graylog = self.graylog-3_3;

  graylog-3_3 = super.callPackage ./graylog {
    jre = getClosureFromStore "/nix/store/5i1mf8784vx7dzh030ixggrx93j3fs9j-openjdk-headless-8u322-ga";
  };

  graylogPlugins = lib.recurseIntoAttrs (
    super.callPackage ./graylog/plugins.nix {
      graylog = self.graylog-3_3;
    }
  );

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

  # PHP versions from vendored nix-phps

  lamp_php72 = self.php72.withExtensions (
    { enabled, all }:
    enabled
    ++ [
      all.bcmath
      all.imagick
      all.memcached
      all.redis
    ]
  );

  lamp_php73 = self.php73.withExtensions (
    { enabled, all }:
    enabled
    ++ [
      all.bcmath
      all.imagick
      all.memcached
      all.redis
    ]
  );

  lamp_php74 = (
    self.php74.withExtensions (
      { enabled, all }:
      enabled
      ++ [
        all.bcmath
        all.imagick
        all.memcached
        all.redis
      ]
    )
  );

  lamp_php80 = (
    self.php80.withExtensions (
      { enabled, all }:
      enabled
      ++ [
        all.bcmath
        all.imagick
        all.memcached
        all.redis
      ]
    )
  );

  # PHP versions from nixpkgs

  lamp_php81 = self.php81.withExtensions (
    { enabled, all }:
    enabled
    ++ [
      all.bcmath
      all.imagick
      all.memcached
      all.redis
    ]
  );

  lamp_php82 = self.php82.withExtensions (
    { enabled, all }:
    enabled
    ++ [
      all.bcmath
      all.imagick
      all.memcached
      all.redis
    ]
  );

  lamp_php83 = self.php83.withExtensions (
    { enabled, all }:
    enabled
    ++ [
      all.bcmath
      all.imagick
      all.memcached
      all.redis
    ]
  );

  lamp_php84 = self.php84.withExtensions (
    { enabled, all }:
    enabled
    ++ [
      all.bcmath
      all.imagick
      all.memcached
      all.redis
    ]
  );

  lamp_php85 = self.php85.withExtensions (
    { enabled, all }:
    enabled
    ++ [
      all.bcmath
      all.imagick
      all.memcached
      all.redis
    ]
  );

  libpcap-vxlan = super.libpcap.overrideAttrs (old: {
    pname = "libpcap-vxlan";
    patches = old.patches or [ ] ++ [
      ./libpcap-replace-geneve-with-vxlan.patch
    ];
  });

  libxcrypt-with-sha256 = super.libxcrypt.override {
    enableHashes = "strong,sha256crypt";
  };

  links2_nox = super.links2.override {
    enableX11 = false;
    enableFB = false;
  };

  lkl = super.lkl.overrideAttrs (_: {
    prePatch = ''
      substituteInPlace tools/lkl/cptofs.c \
        --replace mem=100M mem=500M
    '';
  });

  mysql = super.mariadb;

  monitoring-plugins =
    let
      binPath = lib.makeBinPath (
        with self;
        [
          (placeholder "out")
          "/run/wrappers"
          coreutils
          gnugrep
          gnused
          lm_sensors
          net-snmp
          procps
          unixtools.ping
        ]
      );
      ping = "${self.unixtools.ping}/bin/ping";
    in
    super.monitoring-plugins.overrideAttrs (_: {
      # Taken from upstream postPatch, but with an absolute path for ping instead
      # of relying on PATH. Looks like PATH doesn't apply to check_ping (it's a C
      # program and not a script like other checks), so check_ping needs to
      # be compiled with the full path.
      postPatch = ''
        sed -i configure.ac \
          -e 's|^DEFAULT_PATH=.*|DEFAULT_PATH=\"${binPath}\"|'

        configureFlagsArray+=(
          --with-ping-command='${ping} -4 -n -U -w %d -c %d %s'
          --with-ping6-command='${ping} -6 -n -U -w %d -c %d %s'
        )
      '';

      # These checks are not included by default.
      # Our platform doesn't use them, maybe some customer?
      postInstall = (super.monitoring-plugins.postInstall or "") + ''
        cp plugins-root/check_dhcp $out/bin
        cp plugins-root/check_icmp $out/bin
      '';
    });

  # This is our default version.
  nginxStable =
    (super.nginxStable.override {
      modules = with super.nginxModules; [
        dav
        modsecurity
        moreheaders
        rtmp
      ];
    }).overrideAttrs
      (
        a:
        a
        // {
          patches = a.patches ++ [
            ./remote_addr_anon.patch
          ];
        }
      );

  nginx = self.nginxStable;

  nginxMainline =
    (super.nginxMainline.override {
      modules = with super.nginxModules; [
        dav
        modsecurity
        rtmp
      ];
    }).overrideAttrs
      (a: {
        patches = a.patches ++ [
          ./remote_addr_anon.patch
        ];
      });

  nginxLegacyCrypt = self.nginx.overrideAttrs (old: {
    strictDeps = true;
    buildInputs = [ self.libxcrypt-legacy ] ++ old.buildInputs;
  });

  opensearch-dashboards = super.callPackage ./opensearch-dashboards { };

  opensearch_3_5 = lib.warnOnInstantiate "'opensearch_3_5' has been replaced by 'opensearch'." super.opensearch;

  percona = self.percona84;
  percona-toolkit = super.perlPackages.PerconaToolkit.overrideAttrs (oldAttrs: {
    # The script uses usr/bin/env perl and the Perl builder adds PERL5LIB to it.
    # This doesn't work. Looks like a bug in Nixpkgs.
    # Replacing the interpreter path before the Perl builder touches it fixes this.
    postPatch = oldAttrs.postPatch + ''
      patchShebangs .
    '';
  });

  percona84 = self.percona-server_8_4;

  # Has been renamed upstream, backy-extract still wants to use it.
  pkgconfig = super.pkg-config;

  # fetched from a different flake input, but make easily available via our overlay
  inherit poetry2nix;

  postfix = super.postfix.override {
    cyrus_sasl = self.cyrus_sasl-legacyCrypt;
  };

  python27 = super.python27.overrideAttrs (prev: {
    buildInputs = prev.buildInputs ++ [ super.libxcrypt-legacy ];
    NIX_LDFLAGS = "-lcrypt";
    configureFlags = [
      "CFLAGS=-I${super.libxcrypt-legacy}/include"
      "LIBS=-L${super.libxcrypt-legacy}/lib"
    ];
  });

  qemu-ceph-nautilus = fc-nixos-21_05.qemu-ceph-nautilus;
  # pacific: let's also try a qemu version update from 6.0 to 10.1, because
  # pacific does not compile against old qemu
  qemu-ceph-pacific = super.qemu.override {
    cephSupport = true;
    ceph = self.ceph-pacific.ceph;
  };

  # Ruby 2.7 is EOL but we still need it for Sensu until Aramaki takes over ;)
  #ruby_2_7 = getClosureFromStore /nix/store/qqc6v89xn0g2w123wx85blkpc4pz2ags-ruby-2.7.8;

  sensu = getClosureFromStore /nix/store/3ya2sq1nl4i616mc40kpmag9ndhzj5fy-sensu-1.9.0;

  sensu-plugins-elasticsearch = getClosureFromStore /nix/store/dawyv3kzr69qj2lq8cfm0j941i2hjnfb-sensu-plugins-elasticsearch-4.2.2;
  sensu-plugins-kubernetes = getClosureFromStore /nix/store/cndsgrdmqlgdwc6hnvvrji17jlr7z15k-sensu-plugins-kubernetes-4.0.0;
  sensu-plugins-memcached = getClosureFromStore /nix/store/9hw039bi9zkr33i5vm66403wkf5cqpnc-sensu-plugins-memcached-0.1.3;
  sensu-plugins-mysql = getClosureFromStore /nix/store/ng5blik2ajm6hb5i4ay57yyzbiy5ana0-sensu-plugins-mysql-3.1.1;
  sensu-plugins-disk-checks = getClosureFromStore /nix/store/kmrapdk57468z9zcl57wk1vhz550naqm-sensu-plugins-disk-checks-5.1.4;
  sensu-plugins-entropy-checks = getClosureFromStore /nix/store/fa43q081m3hgvb2lkrqrmjki9349llrv-sensu-plugins-entropy-checks-1.0.0;
  sensu-plugins-http = getClosureFromStore /nix/store/b297df4389l1nrfbsh70x73qqfgamhq0-sensu-plugins-http-6.1.0;
  sensu-plugins-logs = getClosureFromStore /nix/store/cxya5kgd5rksqvqq4mx1cim32wv9nzr2-sensu-plugins-logs-4.1.1;
  sensu-plugins-network-checks = getClosureFromStore /nix/store/155c327fy4din77fv4sk6xzc1k8afbam-sensu-plugins-network-checks-4.0.0;
  sensu-plugins-postfix = getClosureFromStore /nix/store/ac14jxfzl77nm09i4w2p6mrbl6fj6ri4-sensu-plugins-postfix-1.0.0;
  sensu-plugins-postgres = getClosureFromStore /nix/store/mzlxvlfwn8bga044vdabpzdcqwjjblr1-sensu-plugins-postgres-4.2.0;
  sensu-plugins-rabbitmq = getClosureFromStore /nix/store/lcvrxlakcxiqzvwq7g284nhzqfc5gvjv-sensu-plugins-rabbitmq-8.1.0;
  sensu-plugins-redis = getClosureFromStore /nix/store/qbqnynpw5mzx98nz8lx89gpjw91wyd5b-sensu-plugins-redis-4.1.0;

  slurm-25_11 = lib.warnOnInstantiate "'slurm-25_11' has been replaced by 'slurm'." super.slurm;
  solr = super.callPackage ./solr { };

  tcpdump =
    (super.tcpdump.override {
      libpcap = self.libpcap-vxlan;
    }).overrideAttrs
      (old: {
        pname = "tcpdump-vxlan";
      });

  # XXX: consider upstreaming these
  writers = super.writers // {
    /**
       writePython3BinFromFile takes a path to a python file and an attributeset with some further options.
       It outputs a directory with `bin/basename_of_python_file`.
       Attrset options:
       - dependencies: list of packages with executables that are added to PATH for the python program
       - all other options are passed through to `writePython3Bin`.

       # Examples
       :::{.example}
       ## `writePython3BinFromFile` usage example

       ```nix
       writePython3BinFromFile ./pkgs/test.py {
         dependencies = [ pkgs.sl ];
         libraries = [ pkgs.python3Packages.pyyaml ];
       }
       ```

       :::
    */
    writePython3BinFromFile =
      path:
      {
        dependencies ? [ ],
        ...
      }@args:
      let
        progname = lib.removeSuffix ".py" (builtins.baseNameOf path);
        writerArgs = lib.removeAttrs args [ "dependencies" ];
        python3Writer = self.writers.writePython3Bin progname writerArgs (lib.readFile path);
        pathWrapper =
          self.runCommand "wrap-${progname}"
            {
              nativeBuildInputs = [ self.makeBinaryWrapper ];
              meta.mainProgram = progname;
            }
            ''
              mkdir -p $out/bin
              makeBinaryWrapper ${lib.getExe python3Writer} $out/bin/${progname} \
                --prefix PATH : "${lib.makeBinPath dependencies}"
            '';
      in
      if dependencies == [ ] then python3Writer else pathWrapper;
  };

  xtrabackup = lib.warn "The `xtrabackup` package has been renamed to `percona-xtrabackup`." self.percona-xtrabackup;

  wazuh-agent = self.callPackage ./wazuh/agent { };
}
