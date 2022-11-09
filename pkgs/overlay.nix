self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  # We want to have the last available OSS version for Kibana and Elasticsearch.
  # We don't override the global elk7Version because it's ok to use newer versions
  # for the (free) beats and unfree Elasticsearch/Kibana.
  elasticKibana7Version = "7.10.2";

  # import fossar/nix-phps overlay with nixpkgs-unstable's generic.nix copied in
  # then use release-set as pkgs
  phps = (import ../nix-phps/pkgs/phps.nix) (../nix-phps)
    {} super;

  inherit (super) fetchpatch fetchurl lib;

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

  bash_5_1_p12 = super.callPackage ./bash/5.1.nix { };
  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = super.callPackage ./certmgr.nix {  };

  cgmemtime = super.callPackage ./cgmemtime.nix { };
  check_ipmi_sensor = super.callPackage ./check_ipmi_sensor.nix { };
  check_md_raid = super.callPackage ./check_md_raid { };
  check_megaraid = super.callPackage ./check_megaraid { };

  # XXX: ceph doesn't build
  # ceph = (super.callPackage ./ceph {
  #     pythonPackages = super.python3Packages;
  #     boost = super.boost155;
  # });

  # Xen is marked as broken and it's a dependency of the collectd xen plugin.
  # Arguments to the collectd function also get passed to all plugins so this
  # override is effective.
  # We don't use collectd but it's a dependency of influxdb which is needed
  # for statshost.
  collectd = super.collectd.override { xen = null; };

  docsplit = super.callPackage ./docsplit { };

  elasticsearch6 = (super.elasticsearch6.override {
    jre_headless = self.jdk11_headless;
  });

  elasticsearch6-oss = (super.elasticsearch6-oss.override {
    jre_headless = self.jdk11_headless;
  });

  elasticsearch7 = (super.elasticsearch7.override {
    jre_headless = self.jdk11_headless;
  }).overrideAttrs(_: rec {
    version = elasticKibana7Version;
    name = "elasticsearch-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "07p16n53fg513l4f04zq10hh5j9q6rjwz8hs8jj8y97jynvf6yiv";
    };
  });

  elasticsearch7-oss = (super.elasticsearch7.override {
    jre_headless = self.jdk11_headless;
  }).overrideAttrs(_: rec {
    version = elasticKibana7Version;
    name = "elasticsearch-oss-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "1m6wpxs56qb6n473hawfw2n8nny8gj3dy8glq4x05005aa8dv6kh";
    };
    meta.license = lib.licenses.asl20;
  });

  flannel = super.flannel.overrideAttrs(_: rec {
    version = "0.13.1-rc1";
    rev = "v${version}";

    src = super.fetchFromGitHub {
      inherit rev;
      owner = "coreos";
      repo = "flannel";
      sha256 = "119sf1fziznrx7y9ml7h4cqfy0hyl34sbxm81rwjg2svwz0qx6x1";
    };
  });

  graylog = (super.graylog.override {
    openjdk11_headless = self.jdk8_headless;
  });

  kibana7 = super.callPackage ./kibana/7.x.nix { inherit elasticKibana7Version; unfree = true; };
  kibana7-oss = super.callPackage ./kibana/7.x.nix { inherit elasticKibana7Version; };

  # From nixos-unstable 1f5891a700b11ee9afa07074395e1e30799bf392
  kubernetes-helm = super.callPackage ./helm { };

  innotop = super.callPackage ./percona/innotop.nix { };

  libmodsecurity = super.callPackage ./libmodsecurity { };

  jicofo = super.jicofo.overrideAttrs(oldAttrs: rec {
    pname = "jicofo";
    version = "1.0-900";
    src = fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      hash = "sha256-tAuWhu1DdasOuLIz9/Ox1n1XcFWm5qnTVr6FpdKpwbE=";
    };
  });

  jitsi-meet = super.jitsi-meet.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-meet";
    version = "1.0.6260";
    src = fetchurl {
      url = "https://download.jitsi.org/jitsi-meet/src/jitsi-meet-${version}.tar.bz2";
      hash = "sha256-Y1ELKdFdbnq20yUt4XoXmstJm8uI8EBGIFOvFWf+5Uw=";
    };

  });

  jitsi-videobridge = super.jitsi-videobridge.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-videobridge2";
    version = "2.2-9-g8cded16e";
    src = fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      hash = "sha256-L9h+qYV/W2wPzycfDGC4AXpTl7wlulyt2KryA+Tb/YU=";
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

  # This also propagates to the jre* and *_headless variants.
  openjdk8 = super.openjdk8.override { zlib = self.zlibCrcInputFix; };
  openjdk11 = super.openjdk11.override { zlib = self.zlibCrcInputFix; };
  openjdk17 = super.openjdk17.override { zlib = self.zlibCrcInputFix; };

  inherit (super.callPackages ./matomo {})
    matomo
    matomo-beta;


  k3s = super.callPackage ./k3s { buildGoModule = super.buildGo117Module; };
  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };
  kubernetes-dashboard-metrics-scraper = super.callPackage ./kubernetes-dashboard-metrics-scraper.nix { };

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

  filebeat7-oss = super.filebeat7.overrideAttrs(a: a // {
    name = "filebeat-oss-${a.version}";
    preBuild = "rm -rf x-pack";
  });

  # Import old php versions from nix-phps
  inherit (phps) php72 php73;

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

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

  lamp_php74 = (super.php74.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ])).override { pcre2 = self.pcre1035; };

  lamp_php80 = (super.php80.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ])).override { pcre2 = self.pcre1035; };

  pcre1035 = super.pcre2.overrideAttrs (oldAttrs: rec {
    version = "10.35";
    src = super.fetchurl {
      url = "https://github.com/PhilipHazel/pcre2/releases/download/pcre2-${version}/pcre2-${version}.tar.bz2";
      hash = "sha256:04s6kmk9qdd4rjz477h547j4bx7hfz0yalpvrm381rqc5ghaijww";
    };
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
      moreheaders
      rtmp
    ];
  }).overrideAttrs(a: a // {
    patches = a.patches ++ [
      ./remote_addr_anon.patch
    ];
  });

  percona = self.percona80;
  percona-toolkit = super.perlPackages.PerconaToolkit.overrideAttrs(oldAttrs: {
    # The script uses usr/bin/env perl and the Perl builder adds PERL5LIB to it.
    # This doesn't work. Looks like a bug in Nixpkgs.
    # Replacing the interpreter path before the Perl builder touches it fixes this.
    postPatch = ''
      patchShebangs .
    '';
  });

  percona56 = super.callPackage ./percona/5.6.nix { boost = self.boost159; };
  percona57 = super.callPackage ./percona/5.7.nix { boost = self.boost159; };
  percona80 = super.callPackage ./percona/8.0.nix { boost = self.boost173; };

  # We use 2.4 from upstream for older Percona versions.
  # Percona 8.0 needs a newer version than upstream provides.
  percona-xtrabackup_8_0 = super.callPackage ./percona/xtrabackup.nix {
    boost = self.boost173;
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

  # Speed up NixOS tests by making the 9p file system more efficient.
  qemu = super.qemu.overrideAttrs (o: {
    patches = o.patches ++ [ (super.fetchpatch {
      name = "qemu-9p-performance-fix.patch";
      url = "https://gitlab.com/lheckemann/qemu/-/commit/ca8c4a95a320dba9854c3fd4159ff4f52613311f.patch";
      sha256 = "sha256-9jYpGmD28yJGZU4zlae9BL4uU3iukWdPWpSkgHHvOxI=";
    }) ];
  });

  rabbitmq-server_3_8 = super.rabbitmq-server;

  rum = super.callPackage ./postgresql/rum { };

  sensu = super.callPackage ./sensu { ruby = super.ruby; };
  sensu-plugins-elasticsearch = super.callPackage ./sensuplugins-rb/sensu-plugins-elasticsearch { };
  sensu-plugins-kubernetes = super.callPackage ./sensuplugins-rb/sensu-plugins-kubernetes { };
  sensu-plugins-memcached = super.callPackage ./sensuplugins-rb/sensu-plugins-memcached { };
  sensu-plugins-mysql = super.callPackage ./sensuplugins-rb/sensu-plugins-mysql { };
  sensu-plugins-disk-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-disk-checks { };
  sensu-plugins-entropy-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-entropy-checks { };
  sensu-plugins-http = super.callPackage ./sensuplugins-rb/sensu-plugins-http { };
  sensu-plugins-influxdb = super.callPackage ./sensuplugins-rb/sensu-plugins-influxdb { };
  sensu-plugins-logs = super.callPackage ./sensuplugins-rb/sensu-plugins-logs { };
  sensu-plugins-network-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-network-checks { };
  sensu-plugins-postfix = super.callPackage ./sensuplugins-rb/sensu-plugins-postfix { };
  sensu-plugins-postgres = super.callPackage ./sensuplugins-rb/sensu-plugins-postgres { };
  sensu-plugins-rabbitmq = super.callPackage ./sensuplugins-rb/sensu-plugins-rabbitmq { };
  sensu-plugins-redis = super.callPackage ./sensuplugins-rb/sensu-plugins-redis { };
  sensu-plugins-systemd = super.callPackage ./sensuplugins-rb/sensu-plugins-systemd { };

  # fix CVE-2022-35737
  sqlite = lib.lowPrio (super.sqlite.overrideAttrs (oldAttrs: {
    patches = (if (oldAttrs ? "patches") then oldAttrs.patches else []) ++ [ ./sqlite/CVE-2022-35737.patch];
  }));

  solr = super.solr.override { jre = self.jdk11_headless; };

  sudo = super.sudo.overrideAttrs (oldAttrs: {
    patches = (if (oldAttrs ? "patches") then oldAttrs.patches else []) ++ [
    (fetchpatch {
      name = "CVE-2022-43995.patch";
      url = "https://github.com/sudo-project/sudo/commit/bd209b9f16fcd1270c13db27ae3329c677d48050.patch";
      sha256 = "sha256-JUdoStoSyv6KBPsyzxuMIxqwZMZsjUPj8zUqOSvmZ1A=";
    })];
  });

  temporal_tables = super.callPackage ./postgresql/temporal_tables { };

  tideways_daemon = super.callPackage ./tideways/daemon.nix {};
  tideways_module = super.callPackage ./tideways/module.nix {};

  wkhtmltopdf_0_12_5 = super.callPackage ./wkhtmltopdf/0_12_5.nix { };
  wkhtmltopdf_0_12_6 = super.callPackage ./wkhtmltopdf/0_12_6.nix { };
  wkhtmltopdf = self.wkhtmltopdf_0_12_6;

  xtrabackup = self.percona-xtrabackup_8_0;

  zlibCrcInputFix = super.zlib.overrideAttrs(a: {
    patches = a.patches ++ [ ./zlib-1.12.12-incorrect-crc-inputs-fix.patch ];
  });
}
