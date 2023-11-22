self: super:
let
  versions = import ../versions.nix { pkgs = super; };
  # import fossar/nix-phps overlay with nixpkgs-unstable's generic.nix copied in
  # then use release-set as pkgs
  phps = (import ../nix-phps/pkgs/phps.nix) (../nix-phps)
    {} super;

  inherit (super) fetchpatch fetchFromGitHub fetchurl lib;

in {
  #
  # == our own stuff
  #
  fc = (import ./default.nix {
    pkgs = self;
    # Only used by the agent for now but we should probably use this
    # for all our Python packages and update Python in sync then.
    pythonPackages = self.python310Packages;
  });

  #
  # imports from other nixpkgs versions or local definitions
  #

  apacheHttpdLegacyCrypt = self.apacheHttpd.override {
    aprutil = self.aprutil.override { libxcrypt = self.libxcrypt-legacy; };
  };

  inherit (super.callPackage ./boost { }) boost159;

  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
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

  innotop = super.callPackage ./percona/innotop.nix { };

  libmodsecurity = super.callPackage ./libmodsecurity { };

  jicofo = super.jicofo.overrideAttrs(oldAttrs: rec {
    pname = "jicofo";
    version = "1.0-1027";
    src = fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      hash = "sha256-MX1TpxYPvtRfRG/VQxYANsBrbGHf49SDTfn6R8aNC8I=";
    };
  });

  jitsi-meet = super.jitsi-meet.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-meet";
    version = "1.0.7235";
    src = fetchurl {
      url = "https://download.jitsi.org/jitsi-meet/src/jitsi-meet-${version}.tar.bz2";
      hash = "sha256-OlAInpGl6I5rKgIsO3nXUQfksU326lsSDdiZdCYM3NU=";
    };

  });

  jitsi-videobridge = super.jitsi-videobridge.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-videobridge2";
    version = "2.3-19-gb286dc0c";
    src = fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      hash = "sha256-EPpjGS3aFAQToP9IPrcOPxF43nBHuCZPC2b47Jplg/k=";
    };
    # jvb complained about missing libcrypto.so.3, add openssl 3 here.
    installPhase = ''
      runHook preInstall
      substituteInPlace usr/share/jitsi-videobridge/jvb.sh \
        --replace "exec java" "exec ${self.jre_headless}/bin/java"

      mkdir -p $out/{bin,share/jitsi-videobridge,etc/jitsi/videobridge}
      mv etc/jitsi/videobridge/logging.properties $out/etc/jitsi/videobridge/
      mv usr/share/jitsi-videobridge/* $out/share/jitsi-videobridge/
      ln -s $out/share/jitsi-videobridge/jvb.sh $out/bin/jitsi-videobridge

      # work around https://github.com/jitsi/jitsi-videobridge/issues/1547
      wrapProgram $out/bin/jitsi-videobridge \
        --set VIDEOBRIDGE_GC_TYPE G1GC \
        --set LD_LIBRARY_PATH ${super.lib.getLib super.openssl_3_0}/lib/
      runHook postInstall
    '';
  });

  inherit (super.callPackages ./matomo {})
    matomo
    matomo-beta;


  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };
  kubernetes-dashboard-metrics-scraper = super.callPackage ./kubernetes-dashboard-metrics-scraper.nix { };

  # Overriding the version for Go modules doesn't work properly so we
  # include our own beats.nix here. The other beats below inherit the version
  # change.
  inherit (super.callPackage ./beats.nix {}) filebeat7;

  auditbeat7 = self.filebeat7.overrideAttrs(a: a // {
    name = "auditbeat-${a.version}";

    postFixup = "";

    subPackages = [
      "auditbeat"
    ];
  });

  auditbeat7-oss = self.auditbeat7.overrideAttrs(a: a // {
    name = "auditbeat-oss-${a.version}";
    preBuild = "rm -rf x-pack";
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
    preBuild = "rm -rf x-pack";
  });

  # Import old php versions from nix-phps.
  inherit (phps) php72 php73 php74;

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

  # PHP versions from nixpkgs

  #lamp_php80 = (super.php80.withExtensions ({ enabled, all }:
  #            enabled ++ [
  #              all.bcmath
  #              all.imagick
  #              all.memcached
  #              all.redis
  #            ]));

  lamp_php81 = super.php81.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php82 = super.php82.withExtensions ({ enabled, all }:
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
    version = "2022-05-18";
    src = fetchFromGitHub {
      rev = "10c7b5dee8c424cc2ab754e519ecb73350283ff9";
      owner  = "lkl";
      repo   = "linux";
      sha256 = "sha256-D3HQdKzhB172L62a+8884bNhcv7vm/c941wzbYtbf4I=";
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

  monitoring-plugins = super.monitoring-plugins.overrideAttrs(_: rec {
    name = "monitoring-plugins-2.3.0";

      src = super.fetchFromGitHub {
        owner  = "monitoring-plugins";
        repo   = "monitoring-plugins";
        rev    = "v2.3";
        sha256 = "125w3rnslk9wfpzafbviwag0xvix1fzkhnjdxzb1h5fg58wlgf68";
      };

      patches = [];

      postInstall = super.monitoring-plugins.postInstall + ''
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

  opensearch = super.callPackage ./opensearch { };
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

  percona80 = super.callPackage ./percona/8.0.nix {
    boost = self.boost177;
    openldap = self.openldap_2_4;
    openssl = self.openssl_1_1;
    inherit (super.darwin.apple_sdk.frameworks) CoreServices;
    inherit (super.darwin) cctools developer_cmds DarwinTools;
  };

  percona-xtrabackup_2_4 = super.callPackage ./percona-xtrabackup/2_4.nix {
    boost = self.boost159;
    openssl = self.openssl_1_1;
  };

  # Has been renamed upstream, backy-extract still wants to use it.
  pkgconfig = super.pkg-config;

  postfix = super.postfix.override {
    cyrus_sasl = self.cyrus_sasl-legacyCrypt;
  };

  postgis_2_5 = (super.postgresqlPackages.postgis.override {
      proj = self.proj_7;
    }).overrideAttrs(_: rec {
    version = "2.5.5";
    src = super.fetchurl {
      url = "https://download.osgeo.org/postgis/source/postgis-${version}.tar.gz";
      sha256 = "0547xjk6jcwx44s6dsfp4f4j93qrbf2d2j8qhd23w55a58hs05qj";
    };
  });

  prometheus-elasticsearch-exporter = super.callPackage ./prometheus-elasticsearch-exporter.nix { };

  python27 = super.python27.overrideAttrs (prev: {
    buildInputs = prev.buildInputs ++ [ super.libxcrypt-legacy ];
    NIX_LDFLAGS = "-lcrypt";
    configureFlags = [
      "CFLAGS=-I${super.libxcrypt-legacy}/include"
      "LIBS=-L${super.libxcrypt-legacy}/lib"
    ];
  });

  pythonPackagesExtensions = super.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      pyslurm = python-prev.pyslurm.overridePythonAttrs(_: {
        version = "unstable-2023-10-13";
        src = super.fetchFromGitHub {
          owner = "pyslurm";
          repo = "pyslurm";
          rev = "f7a7d8beb8ceb4e4c1b248bab2ebb995dcae77e2";
          sha256 = "dDHjMkBZHngriwyoZx6VtAIVWJXJPGI7qpv/GBcEWC4=";
        };
      });
    })
  ];

  # This was renamed in NixOS 22.11, nixos-mailserver still refers to the old name.
  pypolicyd-spf = self.spf-engine;

  rabbitmq-server_3_8 = super.rabbitmq-server;

  sensu = super.callPackage ./sensu { };
  sensu-plugins-elasticsearch = super.callPackage ./sensuplugins-rb/sensu-plugins-elasticsearch { };
  sensu-plugins-kubernetes = super.callPackage ./sensuplugins-rb/sensu-plugins-kubernetes { };
  sensu-plugins-memcached = super.callPackage ./sensuplugins-rb/sensu-plugins-memcached { };
  sensu-plugins-mysql = super.callPackage ./sensuplugins-rb/sensu-plugins-mysql { };
  sensu-plugins-disk-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-disk-checks { };
  sensu-plugins-entropy-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-entropy-checks { };
  sensu-plugins-http = super.callPackage ./sensuplugins-rb/sensu-plugins-http { };
  sensu-plugins-logs = super.callPackage ./sensuplugins-rb/sensu-plugins-logs { };
  sensu-plugins-network-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-network-checks { };
  sensu-plugins-postfix = super.callPackage ./sensuplugins-rb/sensu-plugins-postfix { };
  sensu-plugins-postgres = super.callPackage ./sensuplugins-rb/sensu-plugins-postgres { };
  sensu-plugins-rabbitmq = super.callPackage ./sensuplugins-rb/sensu-plugins-rabbitmq { };
  sensu-plugins-redis = super.callPackage ./sensuplugins-rb/sensu-plugins-redis { };

  solr = super.callPackage ./solr { };

  temporal_tables = super.callPackage ./postgresql/temporal_tables { };

  tideways_daemon = super.callPackage ./tideways/daemon.nix {};
  tideways_module = super.callPackage ./tideways/module.nix {};

  wkhtmltopdf_0_12_5 = super.callPackage ./wkhtmltopdf/0_12_5.nix { };
  wkhtmltopdf_0_12_6 = super.callPackage ./wkhtmltopdf/0_12_6.nix { };
  wkhtmltopdf = self.wkhtmltopdf_0_12_6;

  xtrabackup = self.percona-xtrabackup_8_0;
}
