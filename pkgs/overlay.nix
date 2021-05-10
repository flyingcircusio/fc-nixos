self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  elk7Version = "7.10.2";

  nixpkgs_18_03 = import versions.nixpkgs_18_03 {};
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
      boost = super.boost155;
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

  grafana = super.callPackage ./grafana.nix { };

  grub2_full = super.callPackage ./grub/2.0x.nix { };

  innotop = super.callPackage ./percona/innotop.nix { };

  jicofo = super.callPackage ./jicofo { };
  jitsi-meet = super.callPackage ./jitsi-meet { };
  jitsi-videobridge = super.callPackage ./jitsi-videobridge { };

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

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

  lamp_php56 =
    let
      phpIni = super.writeText "php.ini" ''
      ${builtins.readFile "${nixpkgs_18_03.php56}/etc/php.ini"}
      extension = ${nixpkgs_18_03.php56Packages.redis}/lib/php/extensions/redis.so
      extension = ${nixpkgs_18_03.php56Packages.memcached}/lib/php/extensions/memcached.so
      extension = ${nixpkgs_18_03.php56Packages.imagick}/lib/php/extensions/imagick.so
      zend_extension = opcache.so
    '';
    in (nixpkgs_18_03.php56).overrideAttrs (oldAttrs: rec {
      version = "5.6.40";
      name = "php-5.6.40";
      buildInputs = oldAttrs.buildInputs ++ [ super.makeWrapper ];
      src = super.fetchurl {
        url = "http://www.php.net/distributions/php-${version}.tar.bz2";
        sha256 = "005s7w167dypl41wlrf51niryvwy1hfv53zxyyr3lm938v9jbl7z";
      };
      passthru = { phpIni = "${phpIni}"; };
      postInstall = oldAttrs.postInstall or "" + ''
        wrapProgram $out/bin/php \
          --set LOCALE_ARCHIVE ${nixpkgs_18_03.glibcLocales}/lib/locale/locale-archive
      '';
    });

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

     ( {
        src = super.fetchFromGitHub {
          owner = "SpiderLabs";
          repo = "ModSecurity-nginx";
          rev = "v1.0.1";
          sha256 = "0cbb3g3g4v6q5zc6an212ia5kjjad62bidnkm8b70i4qv1615pzf";
        };
        inputs = [ super.curl super.geoip self.libmodsecurity super.libxml2 super.lmdb super.yajl ];
        })

      moreheaders
      rtmp
    ];
  }).overrideAttrs(_: rec {
    src = super.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "nginx";
      rev = "2ad7b63de0391df4c49c887f2929a72658bce329";
      sha256 = "02rnpy1w8ia2yxlbcfvx5d4swdrs8a58grffch9pgr1x11kakvl6";
    };

    configureScript = "./auto/configure";
  });

  nginx = self.nginxStable;

  nginxMainline = super.nginxMainline.override {
    modules = with super.nginxModules; [
      dav

      ( {
        src = super.fetchFromGitHub {
          owner = "SpiderLabs";
          repo = "ModSecurity-nginx";
          rev = "v1.0.1";
          sha256 = "0cbb3g3g4v6q5zc6an212ia5kjjad62bidnkm8b70i4qv1615pzf";
        };
        inputs = [ super.curl super.geoip super.libmodsecurity super.libxml2 super.lmdb super.yajl ];
        })

      moreheaders
      rtmp
    ];
  };

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
  percona80 = super.callPackage ./percona/8.0.nix { boost = self.boost172; };

  postgis_2_5 = super.postgis.overrideAttrs(_: rec {
    version = "2.5.5";
    src = super.fetchurl {
      url = "https://download.osgeo.org/postgis/source/postgis-${version}.tar.gz";
      sha256 = "0547xjk6jcwx44s6dsfp4f4j93qrbf2d2j8qhd23w55a58hs05qj";
    };
  });

  prometheus-elasticsearch-exporter = super.callPackage ./prometheus-elasticsearch-exporter.nix { };

  prosody = super.prosody.overrideAttrs(_: {
    version = "0.11.7"; # also update communityModules
    sha256 = "0iw73ids6lv09pg2fn0cxsm2pvi593md71xk48zbcp28advc1zr8";

    communityModules = super.fetchhg {
      url = "https://hg.prosody.im/prosody-modules";
      rev = "7678b4880719";
      sha256 = "1rpk3jcfhsa9hl7d7y638kprs9in0ljjp1nqxg30w1689v5h85d2";
    };
  });

  rabbitmq-server_3_6_5 = super.callPackage ./rabbitmq-server/3.6.5.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_6_15 = super.callPackage ./rabbitmq-server/3.6.15.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_8 = super.rabbitmq-server;

  remarshal = super.callPackage ./remarshal.nix { };
  rum = super.callPackage ./postgresql/rum { };

  sensu-plugins-elasticsearch = super.callPackage ./sensuplugins-rb/sensu-plugins-elasticsearch { };
  sensu-plugins-kubernetes = super.callPackage ./sensuplugins-rb/sensu-plugins-kubernetes { };
  sensu-plugins-memcached = super.callPackage ./sensuplugins-rb/sensu-plugins-memcached { };
  sensu-plugins-mysql = super.callPackage ./sensuplugins-rb/sensu-plugins-mysql { };
  sensu-plugins-entropy-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-entropy-checks { };
  sensu-plugins-network-checks = super.callPackage ./sensuplugins-rb/sensu-plugins-network-checks { };
  sensu-plugins-postfix = super.callPackage ./sensuplugins-rb/sensu-plugins-postfix { };
  sensu-plugins-postgres = super.callPackage ./sensuplugins-rb/sensu-plugins-postgres { };
  sensu-plugins-rabbitmq = super.callPackage ./sensuplugins-rb/sensu-plugins-rabbitmq { };
  sensu-plugins-redis = super.callPackage ./sensuplugins-rb/sensu-plugins-redis { };
  sensu-plugins-systemd = super.callPackage ./sensuplugins-rb/sensu-plugins-systemd { };

  temporal_tables = super.callPackage ./postgresql/temporal_tables { };
  tideways_daemon = super.callPackage ./tideways/daemon.nix {};
  tideways_module = super.callPackage ./tideways/module.nix {};

  wkhtmltopdf_0_12_4 = super.callPackage ./wkhtmltopdf/0_12_4.nix { };
  wkhtmltopdf_0_12_5 = super.callPackage ./wkhtmltopdf/0_12_5.nix { };
  wkhtmltopdf_0_12_6 = super.callPackage ./wkhtmltopdf/0_12_6.nix { };
  wkhtmltopdf = self.wkhtmltopdf_0_12_6;

  xtrabackup = super.callPackage ./percona/xtrabackup.nix {
    inherit (self) percona;
    boost = self.boost172;
  };

  # === Python ===

  python27 = super.python27.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python27Packages = super.recurseIntoAttrs self.python27.pkgs;
  python2Packages = self.python27Packages;

  python36 = super.python36.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python36Packages = self.python36.pkgs;

  python37 = super.python37.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python37Packages = super.recurseIntoAttrs self.python37.pkgs;

  python38 = super.python38.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python38Packages = super.recurseIntoAttrs self.python38.pkgs;
  python3Packages = self.python38Packages;

}
