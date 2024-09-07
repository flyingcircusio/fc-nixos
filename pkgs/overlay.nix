self: super:
let
  versions = import ../versions.nix { pkgs = super; };
  # import fossar/nix-phps overlay with nixpkgs-unstable's generic.nix copied in
  # then use release-set as pkgs
  phps = (import ../nix-phps/pkgs/phps.nix) (../nix-phps)
    {} super;

  inherit (super) fetchpatch fetchFromGitHub fetchurl lib;
  inherit (builtins) hasAttr storePath;

  getClosureFromStore = path:
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
  # redefined and replaced ba the specific version builder.
  patchPhps = patch: phpPkg: phpPkg.overrideAttrs (prev: {patches = [patch] ++ (prev.extraPatches or []);});

in
builtins.mapAttrs (_: patchPhps phpLogPermissionPatch) {
  #
  # == we need to patch upstream PHP for more liberal fpm log file permissions
  #

  # Import old php versions from nix-phps.
  inherit (phps) php72 php73 php74 php80;
  inherit (super) php81 php82;
}
//
{
  php83 = patchPhps (fetchpatch {
    url = "https://github.com/flyingcircusio/php-src/commit/1a7e4834d94d72564521fffd6ceec5a378693cb7.patch";
    hash = "sha256-MWZdXUsvkpxhC9VVttrINY2E4X+PD7lChgkL3VYlk10=";
  }) super.php83;
}
//
{
  #
  # == our own stuff
  #
  fc = (import ./default.nix {
    pkgs = self;
    # Only used by the agent for now but we should probably use this
    # for all our Python packages and update Python in sync then.
    pythonPackages = self.python311Packages;
  });

  #
  # imports from other nixpkgs versions or local definitions
  #

  apacheHttpdLegacyCrypt = self.apacheHttpd.override {
    aprutil = self.aprutil.override { libxcrypt = self.libxcrypt-legacy; };
  };

  inherit (super.callPackage ./boost { }) boost159;

  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = super.callPackage ./certmgr.nix {  };

  check_ipmi_sensor = super.callPackage ./check_ipmi_sensor.nix { };
  check_md_raid = super.callPackage ./check_md_raid { };
  check_megaraid = super.callPackage ./check_megaraid { };

  # XXX: ceph doesn't build
  # ceph = (super.callPackage ./ceph {
  #     pythonPackages = super.python3Packages;
  #     boost = super.boost155;
  # });

  docsplit = super.callPackage ./docsplit { };

  # Don't make docker 25.x the default yet, we still have old docker
  # installs which use the devicemapper storage driver.
  docker = super.docker_24.overrideAttrs (old: {
    # Workaround for Hydra not reading nixpkgs-config.nix
    meta = builtins.removeAttrs old.meta [ "knownVulnerabilites" ];
  });

  innotop = super.callPackage ./percona/innotop.nix { };

  libmodsecurity = super.callPackage ./libmodsecurity { };

  # We don't try to run matomo from the Nix store like upstream does,
  # so we need an installPhase that is a bit different.
  matomo = super.matomo.overrideAttrs (oldAttrs: {
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share
      cp -ra * $out/share/
      rmdir $out/share/tmp
      runHook postInstall
    '';
  });

  matomo-beta = super.matomo-beta.overrideAttrs (oldAttrs: {
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share
      cp -ra * $out/share/
      rmdir $out/share/tmp
      runHook postInstall
    '';
  });

  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };
  kubernetes-dashboard-metrics-scraper = super.callPackage ./kubernetes-dashboard-metrics-scraper.nix { };

  auditbeat7-oss = self.auditbeat7.overrideAttrs(a: a // {
    name = "auditbeat-oss-${a.version}";
    # XXX: tests break without x-pack (bad!)
    # preBuild = "rm -rf x-pack";
  });

  cyrus_sasl-legacyCrypt = super.cyrus_sasl.override {
    libxcrypt = self.libxcrypt-legacy;
  };

  dovecot = (super.dovecot.override {
    cyrus_sasl = self.cyrus_sasl-legacyCrypt;
  }).overrideAttrs(old: {
    strictDeps = true;
    buildInputs = [ self.libxcrypt-legacy ] ++ old.buildInputs;
  });

  filebeat7-oss = self.filebeat7.overrideAttrs(a: a // {
    name = "filebeat-oss-${a.version}";
    # XXX: tests break without x-pack (bad!)
    # preBuild = "rm -rf x-pack";
  });

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

  # PHP versions from vendored nix-phps

  lamp_php72 = self.php72.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php73 = self.php73.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php74 = (self.php74.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]));

  lamp_php80 = (self.php80.withExtensions ({ enabled, all }:
              enabled ++ [
               all.bcmath
               all.imagick
               all.memcached
               all.redis
             ]));

  #PHP versions from nixpkgs

  lamp_php81 = self.php81.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php82 = self.php82.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php83 = self.php83.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  latencytop_nox = super.latencytop.overrideAttrs(_: {
    buildInputs = with self; [ ncurses glib ];
    makeFlags = [ "HAS_GTK_GUI=" ];
  });

  libxcrypt-with-sha256 = super.libxcrypt.override {
    enableHashes = "strong,sha256crypt";
  };

  links2_nox = super.links2.override { enableX11 = false; enableFB = false; };

  lkl = super.lkl.overrideAttrs(_: rec {
    version = "2023-11-07";
    src = fetchFromGitHub {
      rev = "970883c348b61954a11c8c1ab9a2ab3ff0d89f08";
      owner  = "lkl";
      repo   = "linux";
      hash = "sha256-MpvhYLH3toC5DaxeiQxKlYWjrPoFw+1eWkkX3XIiVQ0=";
    };

    prePatch = ''
      patchShebangs arch/lkl/scripts
      patchShebangs scripts
      substituteInPlace tools/lkl/cptofs.c \
        --replace mem=100M mem=500M
    '';
  });


  mc = super.callPackage ./mc.nix { };

  mysql = super.mariadb;

  monitoring-plugins = let
    binPath = lib.makeBinPath (with self; [
      (placeholder "out")
      "/run/wrappers"
      coreutils
      gnugrep
      gnused
      lm_sensors
      net-snmp
      procps
      unixtools.ping
    ]);
    ping = "${self.unixtools.ping}/bin/ping";
  in
  super.monitoring-plugins.overrideAttrs(_: rec {
    # Taken from upstream postPatch, but with an absolute path for ping instead
    # of relying on PATH. Looks like PATH doesn't apply to check_ping (it's a C
    # program and not a script like other checks), so check_ping needs to
    # be compiled with the full path.
    postPatch = ''
      substituteInPlace po/Makefile.in.in \
        --replace /bin/sh ${self.runtimeShell}

      sed -i configure.ac \
        -e 's|^DEFAULT_PATH=.*|DEFAULT_PATH=\"${binPath}\"|'

      configureFlagsArray+=(
        --with-ping-command='${ping} -4 -n -U -w %d -c %d %s'
        --with-ping6-command='${ping} -6 -n -U -w %d -c %d %s'
      )
    '';

    # These checks are not included by default.
    # Our platform doesn't use them, maybe some customer?
    # XXX: Remove in 24.05 if nobody needs it.
    postInstall = (super.monitoring-plugins.postInstall or "") + ''
      cp plugins-root/check_dhcp $out/bin
      cp plugins-root/check_icmp $out/bin
    '';
  });

  # This is our default version.
  nginxStable = (super.nginxStable.override {
    modules = with super.nginxModules; [
      dav
      modsecurity
      moreheaders
      rtmp
    ];
  }).overrideAttrs(a: a // {
    patches = a.patches ++ [
      ./remote_addr_anon.patch
    ];
  });

  nginx = self.nginxStable;

  nginxMainline = (super.nginxMainline.override {
    modules = with super.nginxModules; [
      dav
      modsecurity
      rtmp
    ];
  }).overrideAttrs(a: rec {
    patches = a.patches ++ [
      ./remote_addr_anon.patch
    ];
  });

  nginxLegacyCrypt = self.nginx.overrideAttrs(old: {
    strictDeps = true;
    buildInputs = [ self.libxcrypt-legacy ] ++ old.buildInputs;
  });

  openldap_2_4 = super.callPackage ./openldap_2_4.nix {
    libxcrypt = self.libxcrypt-legacy;
  };

  opensearch-dashboards = super.callPackage ./opensearch-dashboards { };

  percona = self.percona80;
  percona-toolkit = super.perlPackages.PerconaToolkit.overrideAttrs(oldAttrs: {
    # The script uses usr/bin/env perl and the Perl builder adds PERL5LIB to it.
    # This doesn't work. Looks like a bug in Nixpkgs.
    # Replacing the interpreter path before the Perl builder touches it fixes this.
    postPatch = ''
      patchShebangs .
    '';
  });

  percona57 = super.callPackage ./percona/5.7.nix {
    boost = self.boost159;
    openssl = self.openssl_1_1;
  };

  percona80 = super.percona-server_8_0;

  # assertion notifies us about the need to vendor the old innovation releases
  percona83 = assert self.percona-server_innovation.mysqlVersion == "8.3"; self.percona-server_innovation;

  percona-xtrabackup_2_4 = super.callPackage ./percona-xtrabackup/2_4.nix {
    boost = self.boost159;
    openssl = self.openssl_1_1;
  };

  percona-xtrabackup_8_3 = assert self.percona-xtrabackup_innovation.mysqlVersion == "8.3"; self.percona-xtrabackup_innovation;
  # Has been renamed upstream, backy-extract still wants to use it.
  pkgconfig = super.pkg-config;

  postfix = super.postfix.override {
    cyrus_sasl = self.cyrus_sasl-legacyCrypt;
  };

  prometheus-elasticsearch-exporter = super.callPackage ./prometheus-elasticsearch-exporter.nix { };

  python27 = super.python27.overrideAttrs (prev: {
    buildInputs = prev.buildInputs ++ [ super.libxcrypt-legacy ];
    NIX_LDFLAGS = "-lcrypt";
    configureFlags = [
      "CFLAGS=-I${super.libxcrypt-legacy}/include"
      "LIBS=-L${super.libxcrypt-legacy}/lib"
    ];
  });

  # This was renamed in NixOS 22.11, nixos-mailserver still refers to the old name.
  pypolicyd-spf = self.spf-engine;

  rabbitmq-server_3_8 = super.rabbitmq-server;

  rich-cli = super.rich-cli.overridePythonAttrs (prev: {
    propagatedBuildInputs = with self.python3Packages; [
      rich
      click
      requests
      textual
      rich-rst
    ];
  });

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

  solr = super.callPackage ./solr { };

  xtrabackup = self.percona-xtrabackup_8_0;
}
