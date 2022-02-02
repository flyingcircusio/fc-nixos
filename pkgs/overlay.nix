self: super:

let
  versions = import ../versions.nix { pkgs = super; };

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

  ceph = (super.callPackage ./ceph {
      pythonPackages = super.python3Packages;
      boost = super.boost155;
  });

  # Xen is marked as broken and it's a dependency of the collectd xen plugin.
  # Arguments to the collectd function also get passed to all plugins so this
  # override is effective.
  # We don't use collectd but it's a dependency of influxdb which is needed
  # for statshost.
  collectd = super.collectd.override { xen = null; };

  docsplit = super.callPackage ./docsplit { };

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

  innotop = super.callPackage ./percona/innotop.nix { };

  jibri = super.callPackage ./jibri { jre_headless = super.jre8_headless; };

  jicofo = super.jicofo.overrideAttrs(oldAttrs: rec {
    pname = "jicofo";
    version = "1.0-830";
    src = super.fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      sha256 = "1q3lx0xaxpw7ycxaaphwr1mxv12yskh84frrxv1r27z1gkcdgd3f";
    };
  });

  jitsi-meet = super.jitsi-meet.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-meet";
    version = "1.0.5638";
    src = super.fetchurl {
      url = "https://download.jitsi.org/jitsi-meet/src/jitsi-meet-${version}.tar.bz2";
      sha256 = "1nahja4i8400445zymqmpq7g1gmwxvjrbvinhmpzi42alzvw3kw6";
    };

  });

  jitsi-videobridge = super.jitsi-videobridge.overrideAttrs(oldAttrs: rec {
    pname = "jitsi-videobridge2";
    version = "2.1-595-g3637fda4";
    src = super.fetchurl {
      url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
      sha256 = "18x00lazyjcff8n7pn4h43cxlskv0d9vnh0cmf40ihrpqc5zs2dz";
    };
  });

  inherit (super.callPackages ./matomo {})
    matomo
    matomo-beta;

  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };
  kubernetes-dashboard-metrics-scraper = super.callPackage ./kubernetes-dashboard-metrics-scraper.nix { };

  auditbeat7 = self.filebeat7.overrideAttrs(a: a // {
    name = "auditbeat-${a.version}";

    postFixup = "";

    subPackages = [
      "auditbeat"
    ];
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

  lamp_php74 = super.php74.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php80 = super.php80.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  mc = super.callPackage ./mc.nix { };

  libmodsecurity = super.libmodsecurity.overrideAttrs(_: rec {
      version = "3.0.4";

      src = super.fetchFromGitHub {
        owner = "SpiderLabs";
        repo = "ModSecurity";
        fetchSubmodules = true;
        rev = "v3.0.4";
        sha256 = "07vry10cdll94sp652hwapn0ppjv3mb7n2s781yhy7hssap6f2vp";
      };

    });

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

  temporal_tables = super.callPackage ./postgresql/temporal_tables { };
  tideways_daemon = super.callPackage ./tideways/daemon.nix {};
  tideways_module = super.callPackage ./tideways/module.nix {};

  wkhtmltopdf_0_12_5 = super.callPackage ./wkhtmltopdf/0_12_5.nix { };
  wkhtmltopdf_0_12_6 = super.callPackage ./wkhtmltopdf/0_12_6.nix { };
  wkhtmltopdf = self.wkhtmltopdf_0_12_6;

  xtrabackup = self.percona-xtrabackup_8_0;
}
