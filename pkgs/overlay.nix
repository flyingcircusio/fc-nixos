self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  elk7Version = "7.10.2";

  # import fossar/nix-phps overlay with nixpkgs-unstable's generic.nix copied in
  # then use release-set as pkgs
  phps = (import ../nix-phps/pkgs/phps.nix) (../nix-phps)
    {} super;

  inherit (super) lib;

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

  backy = super.callPackage ./backy.nix { };
  backyExtract = super.callPackage ./backyextract { };

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

  # Hash is wrong upstream
  containerd = super.containerd.overrideAttrs(_: rec {
    version = "1.5.1";

    src = super.fetchFromGitHub {
      rev = "v${version}";
      owner = "containerd";
      repo = "containerd";
      sha256 = "16q34yiv5q98b9d5vgy1lmmppg8agrmnfd1kzpakkf4czkws0p4d";
    };
  });

  docsplit = super.callPackage ./docsplit { };

  elasticsearch7 = super.elasticsearch7.overrideAttrs(_: rec {
    version = elk7Version;
    name = "elasticsearch-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "07p16n53fg513l4f04zq10hh5j9q6rjwz8hs8jj8y97jynvf6yiv";
    };
    meta.license = null;
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

  gitlab = super.callPackage ./gitlab { };
  gitlab-workhorse = super.callPackage ./gitlab/gitlab-workhorse { };

  grub2_full = super.callPackage ./grub/2.0x.nix { };

  innotop = super.callPackage ./percona/innotop.nix { };

  jibri = super.callPackage ./jibri { jre_headless = super.jre8_headless; };

  haproxy = super.haproxy.overrideAttrs(orig: rec {
    version = "2.3.14";
    src = super.fetchurl {
      url = "https://www.haproxy.org/download/${lib.versions.majorMinor version}/src/${orig.pname}-${version}.tar.gz";
      sha256 = "0ah6xsxlk1a7jsxdg0pbdhzhssz9ysrfxd3bs5hm1shql1jmqzh4";
    };
  });

  kibana7 = super.kibana7.overrideAttrs(_: rec {
    version = elk7Version;
    name = "kibana-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/kibana/${name}-linux-x86_64.tar.gz";
      sha256 = "06p0v39ih606mdq2nsdgi5m7y1iynk9ljb9457h5rrx6jakc2cwm";
    };
    meta.license = null;
  });

  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };

  # Import old php versions from nix-phps
  # NOTE: php7.3 is already removed on unstable
  inherit (phps) php56;

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

  lamp_php56 = self.php56.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php73 = super.php73.withExtensions ({ enabled, all }:
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

  mongodb-3_6 = super.mongodb-3_6.overrideAttrs(_: rec {
    meta.license = null;
    version = "3.6.19";
    name = "mongodb-${version}";
    src = super.fetchurl {
      url = "https://fastdl.mongodb.org/src/mongodb-src-r${version}.tar.gz";
      sha256 = "0y0k5lc2czvg8zirvqfnmpv9z0xz2slp2zfacp0hm0kzcnq82m51";
    };
  });
  mongodb-4_0 = super.mongodb-4_0.overrideAttrs(_: rec {
    meta.license = null;
    version = "4.0.19";
    name = "mongodb-${version}";
    src = super.fetchurl {
      url = "https://fastdl.mongodb.org/src/mongodb-src-r${version}.tar.gz";
      sha256 = "1kbw8vjbwlh94y58am0cxdz92mpb4amf575x0p456h1k3kh87rjg";
    };
  });


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

  openssh_8_7 = super.openssh.overrideAttrs(_: rec {
    version = "8.7p1";
    name = "openssh-${version}";

    src = super.fetchurl {
      url = "mirror://openbsd/OpenSSH/portable/openssh-${version}.tar.gz";
      sha256 = "090yxpi03pxxzb4ppx8g8hdpw7c4nf8p0avr6c7ybsaana5lp8vw";
    };

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

  postgis_2_5 = super.postgis.overrideAttrs(_: rec {
    version = "2.5.5";
    src = super.fetchurl {
      url = "https://download.osgeo.org/postgis/source/postgis-${version}.tar.gz";
      sha256 = "0547xjk6jcwx44s6dsfp4f4j93qrbf2d2j8qhd23w55a58hs05qj";
    };
  });

  prometheus-elasticsearch-exporter = super.callPackage ./prometheus-elasticsearch-exporter.nix { };

  rabbitmq-server_3_8 = super.rabbitmq-server;

  remarshal = super.callPackage ./remarshal.nix { };
  rum = super.callPackage ./postgresql/rum { };

  sensu = super.callPackage ./sensu { ruby = super.ruby_2_6; };
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
