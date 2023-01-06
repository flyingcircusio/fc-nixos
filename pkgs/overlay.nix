self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  # We want to have the last available OSS version for Elasticsearch.
  # We don't override the global elk7Version because it's ok to use newer versions
  # for the (free) beats and unfree Elasticsearch
  elastic7Version = "7.10.2";

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
  });

  #
  # imports from other nixpkgs versions or local definitions
  #

  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = super.callPackage ./certmgr.nix {  };

  check_ipmi_sensor = super.callPackage ./check_ipmi_sensor.nix { };
  check_md_raid = super.callPackage ./check_md_raid { };
  check_megaraid = super.callPackage ./check_megaraid { };

  ceph = self.ceph-luminous;
  ceph-jewel = (super.callPackage ./ceph/jewel {
      pythonPackages = super.python2Packages;
      boost = super.boost155;
  });
  ceph-luminous = (super.callPackage ./ceph/luminous {
    boost = super.boost166.override {
      enablePython = true;
      python = self.python27-ceph-downgrades;
    };
    stdenv = self.gcc9Stdenv;
    python2Packages = self.python27-ceph-downgrades.pkgs;
  });


  docsplit = super.callPackage ./docsplit { };

  elasticsearch6-oss = (super.elasticsearch6-oss.override {
    jre_headless = self.jdk11_headless;
  });

  elasticsearch7 = (super.elasticsearch7.override {
    jre_headless = self.jdk11_headless;
  }).overrideAttrs(_: rec {
    version = elastic7Version;

    name = "elasticsearch-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "07p16n53fg513l4f04zq10hh5j9q6rjwz8hs8jj8y97jynvf6yiv";
    };
  });

  elasticsearch7-oss = (super.elasticsearch7.override {
    jre_headless = self.jdk11_headless;
  }).overrideAttrs(_: rec {
    version = elastic7Version;
    name = "elasticsearch-oss-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "1m6wpxs56qb6n473hawfw2n8nny8gj3dy8glq4x05005aa8dv6kh";
    };
    meta.license = lib.licenses.asl20;
  });

  graylog = (super.graylog.override {
    openjdk11_headless = self.jdk8_headless;
  });

  innotop = super.callPackage ./percona/innotop.nix { };

  libmodsecurity = super.callPackage ./libmodsecurity { };

  jicofo = super.jicofo.overrideAttrs(oldAttrs: rec {
    pname = "jicofo";
    version = "1.0-940";
    src = fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      hash = "sha256-vx7aUHfKxG+tZ0sM8eWr1tTKf//bMxdKVhE5I4P4mLo=";
    };
  });

  jitsi-meet = super.jitsi-meet.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-meet";
    version = "1.0.6644";
    src = fetchurl {
      url = "https://download.jitsi.org/jitsi-meet/src/jitsi-meet-${version}.tar.bz2";
      hash = "sha256-y1oI3nxIu7breYNPhdX7PU5GfnCyxdEbAYlyZmif2Uo=";
    };

  });

  jitsi-videobridge = super.jitsi-videobridge.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-videobridge2";
    version = "2.2-45-ge8b20f06";
    src = fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      hash = "sha256-fbSpjLdx9xbLdp7vzHTW9B/cDf3DahpwuI4IcqEqpas=";
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

  filebeat7-oss = self.filebeat7.overrideAttrs(a: a // {
    name = "filebeat-oss-${a.version}";
    preBuild = "rm -rf x-pack";
  });

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

  lamp_php80 = (super.php80.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]));

  lamp_php81 = super.php81.withExtensions ({ enabled, all }:
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
      modsecurity-nginx
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
      modsecurity-nginx
      rtmp
    ];
  }).overrideAttrs(a: rec {
    patches = a.patches ++ [
      ./remote_addr_anon.patch
    ];
    version = "1.23.0";
    src = fetchurl {
      url = "https://nginx.org/download/nginx-${version}.tar.gz";
      hash = "sha256-ggrKo1uScr6ennL23vpKXykhgkcJ+KpHcseKsx7ZTNE=";
  };
  });

  openldap_2_4 = super.callPackage ./openldap_2_4.nix { };

  percona = self.percona80;
  percona-toolkit = super.perlPackages.PerconaToolkit.overrideAttrs(oldAttrs: {
    # The script uses usr/bin/env perl and the Perl builder adds PERL5LIB to it.
    # This doesn't work. Looks like a bug in Nixpkgs.
    # Replacing the interpreter path before the Perl builder touches it fixes this.
    postPatch = ''
      patchShebangs .
    '';
  });

  #percona56 = super.callPackage ./percona/5.6.nix { boost = self.boost159; };
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

  # We use 2.4 from upstream for older Percona versions.
  # Percona 8.0 needs a newer version than upstream provides.
  percona-xtrabackup_8_0 = super.callPackage ./percona/xtrabackup.nix {
    boost = self.boost177;
    openssl = self.openssl_1_1;
  };

  # Has been renamed upstream, backy-extract still wants to use it.
  pkgconfig = super.pkg-config;

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

  # python27 with several downgrades to make required modules work under python27 again
  python27-ceph-downgrades = let thisPy = self.python27-ceph-downgrades;
  in
  super.python27.override {
    packageOverrides = python-self: python-super: {
      babel = thisPy.pkgs.callPackage ./python/babel { };
      cheroot = thisPy.pkgs.callPackage ./python/cheroot { };
      cherrypy = thisPy.pkgs.callPackage ./python/cherrypy { };
      cython = thisPy.pkgs.callPackage ./python/Cython { };
      jaraco_text = thisPy.pkgs.callPackage ./python/jaraco_text { };
      Mako = thisPy.pkgs.callPackage ./python/Mako { };
      PasteDeploy = python-super.PasteDeploy.overrideAttrs (oldattrs: {
        # for pkg_resources
        propagatedBuildInputs = oldattrs.propagatedBuildInputs ++ [python-self.setuptools];
      });
      pathpy = thisPy.pkgs.callPackage ./python/path.py { };
      pecan = thisPy.pkgs.callPackage ./python/pecan { };
      portend = thisPy.pkgs.callPackage ./python/portend { };
      pypytools = thisPy.pkgs.callPackage ./python/pypytools { };
      pyquery = thisPy.pkgs.callPackage ./python/pyquery { };
      pytestcov = thisPy.pkgs.callPackage ./python/pytest-cov { };
      routes = python-super.routes.overrideAttrs (oldattrs: {
        # work around a weird pythonImportsCheck failure, but cannot be empty
        pythonImportsCheckPhase = "true";
      });
      singledispatch = thisPy.pkgs.callPackage ./python/singledispatch { };
      SQLAlchemy = thisPy.pkgs.callPackage ./python/sqlalchemy { };
      tempora = thisPy.pkgs.callPackage ./python/tempora { };
      waitress = thisPy.pkgs.callPackage ./python/waitress { };
      webob = thisPy.pkgs.callPackage ./python/webob { };
      webtest = thisPy.pkgs.callPackage ./python/webtest {
        pastedeploy = python-self.PasteDeploy;
      };
      WebTest = python-self.webtest;
      zc_lockfile = thisPy.pkgs.callPackage ./python/zc_lockfile { };
    };
  };

  # This was renamed in NixOS 22.11, nixos-mailserver still refers to the old name.
  pypolicyd-spf = self.spf-engine;

  # Speed up NixOS tests by making the 9p file system more efficient.
  qemu = super.qemu.overrideAttrs (o: {
    patches = o.patches ++ [ (super.fetchpatch {
      name = "qemu-9p-performance-fix.patch";
      url = "https://gitlab.com/lheckemann/qemu/-/commit/ca8c4a95a320dba9854c3fd4159ff4f52613311f.patch";
      sha256 = "sha256-9jYpGmD28yJGZU4zlae9BL4uU3iukWdPWpSkgHHvOxI=";
    }) ];
  });

  qemu_ceph = super.qemu.override { cephSupport = true; };

  rabbitmq-server_3_8 = super.rabbitmq-server;

  sensu = super.callPackage ./sensu { ruby = super.ruby; };
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
  sensu-plugins-systemd = super.callPackage ./sensuplugins-rb/sensu-plugins-systemd { };

  temporal_tables = super.callPackage ./postgresql/temporal_tables { };

  tideways_daemon = super.callPackage ./tideways/daemon.nix {};
  tideways_module = super.callPackage ./tideways/module.nix {};

  wkhtmltopdf_0_12_5 = super.callPackage ./wkhtmltopdf/0_12_5.nix { };
  wkhtmltopdf_0_12_6 = super.callPackage ./wkhtmltopdf/0_12_6.nix { };
  wkhtmltopdf = self.wkhtmltopdf_0_12_6;

  xtrabackup = self.percona-xtrabackup_8_0;
}
