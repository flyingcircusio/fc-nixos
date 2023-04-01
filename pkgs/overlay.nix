final: prev:
let
  versions = import ../versions.nix { pkgs = prev; };
  # import fossar/nix-phps overlay with nixpkgs-unstable's generic.nix copied in
  # then use release-set as pkgs
  phps = (import ../nix-phps/pkgs/phps.nix) (../nix-phps)
    {} prev;

  inherit (prev) fetchpatch fetchFromGitHub fetchurl lib;

in {
  #
  # == our own stuff
  #
  fc = (import ./default.nix {
    pkgs = final;
    # Only used by the agent for now but we should probably use this
    # for all our Python packages and update Python in sync then.
    pythonPackages = final.python310Packages;
  });

  #
  # imports from other nixpkgs versions or local definitions
  #

  apacheHttpdLegacyCrypt = final.apacheHttpd.override {
    aprutil = final.aprutil.override { libxcrypt = final.libxcrypt-legacy; };
  };

  inherit (prev.callPackage ./boost { }) boost159;

  bundlerSensuPlugin = prev.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = prev.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = prev.callPackage ./certmgr.nix {  };

  check_ipmi_sensor = prev.callPackage ./check_ipmi_sensor.nix { };
  check_md_raid = prev.callPackage ./check_md_raid { };
  check_megaraid = prev.callPackage ./check_megaraid { };

  # XXX: ceph doesn't build
  # ceph = (super.callPackage ./ceph {
  #     pythonPackages = super.python3Packages;
  #     boost = super.boost155;
  # });

  docsplit = prev.callPackage ./docsplit { };

  innotop = prev.callPackage ./percona/innotop.nix { };

  # XXX: pinned to the latest 16.1.0 version using Go 1.20.5 (from release 2023_017)
  # until the gitlab-runner problem with Go 1.20.6 is fixed:
  # https://gitlab.com/gitlab-org/gitlab-runner/-/issues/36051 and
  # https://github.com/NixOS/nixpkgs/issues/245365
  gitlab-runner = builtins.storePath /nix/store/hfk8w6yf0zfvs6ng1swpiyrqrk5pghn5-gitlab-runner-16.1.0;

  libmodsecurity = prev.callPackage ./libmodsecurity { };

  jicofo = prev.jicofo.overrideAttrs(oldAttrs: rec {
    pname = "jicofo";
    version = "1.0-1027";
    src = fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      hash = "sha256-MX1TpxYPvtRfRG/VQxYANsBrbGHf49SDTfn6R8aNC8I=";
    };
  });

  jitsi-meet = prev.jitsi-meet.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-meet";
    version = "1.0.7235";
    src = fetchurl {
      url = "https://download.jitsi.org/jitsi-meet/src/jitsi-meet-${version}.tar.bz2";
      hash = "sha256-OlAInpGl6I5rKgIsO3nXUQfksU326lsSDdiZdCYM3NU=";
    };

  });

  jitsi-videobridge = prev.jitsi-videobridge.overrideAttrs(oldAttrs: rec {
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
        --replace "exec java" "exec ${final.jre_headless}/bin/java"

      mkdir -p $out/{bin,share/jitsi-videobridge,etc/jitsi/videobridge}
      mv etc/jitsi/videobridge/logging.properties $out/etc/jitsi/videobridge/
      mv usr/share/jitsi-videobridge/* $out/share/jitsi-videobridge/
      ln -s $out/share/jitsi-videobridge/jvb.sh $out/bin/jitsi-videobridge

      # work around https://github.com/jitsi/jitsi-videobridge/issues/1547
      wrapProgram $out/bin/jitsi-videobridge \
        --set VIDEOBRIDGE_GC_TYPE G1GC \
        --set LD_LIBRARY_PATH ${prev.lib.getLib prev.openssl_3_0}/lib/
      runHook postInstall
    '';
  });

  inherit (prev.callPackages ./matomo {})
    matomo
    matomo-beta;


  kubernetes-dashboard = prev.callPackage ./kubernetes-dashboard.nix { };
  kubernetes-dashboard-metrics-scraper = prev.callPackage ./kubernetes-dashboard-metrics-scraper.nix { };

  # Overriding the version for Go modules doesn't work properly so we
  # include our own beats.nix here. The other beats below inherit the version
  # change.
  inherit (prev.callPackage ./beats.nix {}) filebeat7;

  auditbeat7 = final.filebeat7.overrideAttrs(a: a // {
    name = "auditbeat-${a.version}";

    postFixup = "";

    subPackages = [
      "auditbeat"
    ];
  });

  auditbeat7-oss = final.auditbeat7.overrideAttrs(a: a // {
    name = "auditbeat-oss-${a.version}";
    preBuild = "rm -rf x-pack";
  });

  cyrus_sasl-legacyCrypt = prev.cyrus_sasl.override {
    libxcrypt = final.libxcrypt-legacy;
  };

  dovecot = (prev.dovecot.override {
    cyrus_sasl = final.cyrus_sasl-legacyCrypt;
  }).overrideAttrs(old: {
    strictDeps = true;
    buildInputs = [ final.libxcrypt-legacy ] ++ old.buildInputs;
  });

  filebeat7-oss = final.filebeat7.overrideAttrs(a: a // {
    name = "filebeat-oss-${a.version}";
    preBuild = "rm -rf x-pack";
  });

  # Import old php versions from nix-phps.
  inherit (phps) php72 php73 php74;

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

  # PHP versions from vendored nix-phps

  lamp_php72 = final.php72.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php73 = final.php73.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php74 = (final.php74.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]));

  # PHP versions from nixpkgs

  lamp_php80 = (prev.php80.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]));

  lamp_php81 = prev.php81.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php82 = prev.php82.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  latencytop_nox = prev.latencytop.overrideAttrs(_: {
    buildInputs = with final; [ ncurses glib ];
    makeFlags = [ "HAS_GTK_GUI=" ];
  });

  libxcrypt-with-sha256 = prev.libxcrypt.override {
    enableHashes = "strong,sha256crypt";
  };

  links2_nox = prev.links2.override { enableX11 = false; enableFB = false; };

  lkl = prev.lkl.overrideAttrs(_: rec {
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


  mc = prev.callPackage ./mc.nix { };

  mysql = prev.mariadb;

  monitoring-plugins = prev.monitoring-plugins.overrideAttrs(_: rec {
    name = "monitoring-plugins-2.3.0";

      src = prev.fetchFromGitHub {
        owner  = "monitoring-plugins";
        repo   = "monitoring-plugins";
        rev    = "v2.3";
        sha256 = "125w3rnslk9wfpzafbviwag0xvix1fzkhnjdxzb1h5fg58wlgf68";
      };

      patches = [];

      postInstall = prev.monitoring-plugins.postInstall + ''
        cp plugins-root/check_dhcp $out/bin
        cp plugins-root/check_icmp $out/bin
      '';

    });

  # This is our default version.
  nginxStable = (prev.nginxStable.override {
    modules = with prev.nginxModules; [
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

  nginx = final.nginxStable;

  nginxMainline = (prev.nginxMainline.override {
    modules = with prev.nginxModules; [
      dav
      modsecurity
      rtmp
    ];
  }).overrideAttrs(a: rec {
    patches = a.patches ++ [
      ./remote_addr_anon.patch
    ];
  });

  nginxLegacyCrypt = final.nginx.overrideAttrs(old: {
    strictDeps = true;
    buildInputs = [ final.libxcrypt-legacy ] ++ old.buildInputs;
  });

  openldap_2_4 = prev.callPackage ./openldap_2_4.nix {
    libxcrypt = final.libxcrypt-legacy;
  };

  opensearch = prev.callPackage ./opensearch { };
  opensearch-dashboards = prev.callPackage ./opensearch-dashboards { };

  percona = final.percona80;
  percona-toolkit = prev.perlPackages.PerconaToolkit.overrideAttrs(oldAttrs: {
    # The script uses usr/bin/env perl and the Perl builder adds PERL5LIB to it.
    # This doesn't work. Looks like a bug in Nixpkgs.
    # Replacing the interpreter path before the Perl builder touches it fixes this.
    postPatch = ''
      patchShebangs .
    '';
  });

  percona57 = prev.callPackage ./percona/5.7.nix {
    boost = final.boost159;
    openssl = final.openssl_1_1;
  };

  percona80 = prev.callPackage ./percona/8.0.nix {
    boost = final.boost177;
    openldap = final.openldap_2_4;
    openssl = final.openssl_1_1;
    inherit (prev.darwin.apple_sdk.frameworks) CoreServices;
    inherit (prev.darwin) cctools developer_cmds DarwinTools;
  };

  percona-xtrabackup_2_4 = prev.callPackage ./percona-xtrabackup/2_4.nix {
    boost = final.boost159;
    openssl = final.openssl_1_1;
  };

  percona-xtrabackup_8_0 = prev.callPackage ./percona-xtrabackup/8_0.nix {
    boost = final.boost177;
    openssl = final.openssl_1_1;
  };

  # Has been renamed upstream, backy-extract still wants to use it.
  pkgconfig = prev.pkg-config;

  postfix = prev.postfix.override {
    cyrus_sasl = final.cyrus_sasl-legacyCrypt;
  };

  postgis_2_5 = (prev.postgresqlPackages.postgis.override {
      proj = final.proj_7;
    }).overrideAttrs(_: rec {
    version = "2.5.5";
    src = prev.fetchurl {
      url = "https://download.osgeo.org/postgis/source/postgis-${version}.tar.gz";
      sha256 = "0547xjk6jcwx44s6dsfp4f4j93qrbf2d2j8qhd23w55a58hs05qj";
    };
  });

  prometheus-elasticsearch-exporter = prev.callPackage ./prometheus-elasticsearch-exporter.nix { };

  python27 = prev.python27.overrideAttrs (prev: {
    buildInputs = prev.buildInputs ++ [ final.libxcrypt-legacy ];
    NIX_LDFLAGS = "-lcrypt";
    configureFlags = [
      "CFLAGS=-I${final.libxcrypt-legacy}/include"
      "LIBS=-L${final.libxcrypt-legacy}/lib"
    ];
  });

  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      pyslurm = python-prev.pyslurm.overridePythonAttrs(_: {
        version = "unstable-2023-05-12";
        src = prev.fetchFromGitHub {
          owner = "pyslurm";
          repo = "pyslurm";
          rev = "42471d8575e89caa64fea55677d1af130328b4a7";
          sha256 = "K9RqWe0EPvf/0Hs2XBpII/OEqoo0Kr+dFZKioQafbXI=";
        };
      });
    })
  ];

  # This was renamed in NixOS 22.11, nixos-mailserver still refers to the old name.
  pypolicyd-spf = final.spf-engine;

  rabbitmq-server_3_8 = prev.rabbitmq-server;

  sensu = prev.callPackage ./sensu { };
  sensu-plugins-elasticsearch = prev.callPackage ./sensuplugins-rb/sensu-plugins-elasticsearch { };
  sensu-plugins-kubernetes = prev.callPackage ./sensuplugins-rb/sensu-plugins-kubernetes { };
  sensu-plugins-memcached = prev.callPackage ./sensuplugins-rb/sensu-plugins-memcached { };
  sensu-plugins-mysql = prev.callPackage ./sensuplugins-rb/sensu-plugins-mysql { };
  sensu-plugins-disk-checks = prev.callPackage ./sensuplugins-rb/sensu-plugins-disk-checks { };
  sensu-plugins-entropy-checks = prev.callPackage ./sensuplugins-rb/sensu-plugins-entropy-checks { };
  sensu-plugins-http = prev.callPackage ./sensuplugins-rb/sensu-plugins-http { };
  sensu-plugins-logs = prev.callPackage ./sensuplugins-rb/sensu-plugins-logs { };
  sensu-plugins-network-checks = prev.callPackage ./sensuplugins-rb/sensu-plugins-network-checks { };
  sensu-plugins-postfix = prev.callPackage ./sensuplugins-rb/sensu-plugins-postfix { };
  sensu-plugins-postgres = prev.callPackage ./sensuplugins-rb/sensu-plugins-postgres { };
  sensu-plugins-rabbitmq = prev.callPackage ./sensuplugins-rb/sensu-plugins-rabbitmq { };
  sensu-plugins-redis = prev.callPackage ./sensuplugins-rb/sensu-plugins-redis { };

  solr = prev.callPackage ./solr { };

  temporal_tables = prev.callPackage ./postgresql/temporal_tables { };

  tideways_daemon = prev.callPackage ./tideways/daemon.nix {};
  tideways_module = prev.callPackage ./tideways/module.nix {};

  wkhtmltopdf_0_12_5 = prev.callPackage ./wkhtmltopdf/0_12_5.nix { };
  wkhtmltopdf_0_12_6 = prev.callPackage ./wkhtmltopdf/0_12_6.nix { };
  wkhtmltopdf = final.wkhtmltopdf_0_12_6;

  xtrabackup = final.percona-xtrabackup_8_0;
}
