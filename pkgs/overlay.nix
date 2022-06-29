self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  elk7Version = "7.10.2";

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

  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = super.callPackage ./certmgr.nix {  };

  cgmemtime = super.callPackage ./cgmemtime.nix { };
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
    python3ForDocBuilding = self.python3.override {
      packageOverrides = python-self: python-super: {
        # downgrading, because sphinx-ditaa only compatible until sphinx-1.6.7...
        sphinx = self.python3.pkgs.callPackage ./python/sphinx { };
        # ...which also requires downgrading breathe
        breathe = self.python3.pkgs.callPackage ./python/breathe { sphinx = python-self.sphinx; };
        sphinx-ditaa = self.python3.pkgs.callPackage ./python/sphinx-ditaa { sphinx = python-self.sphinx; };
      };
    };
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

  elasticsearch7 = (super.elasticsearch7.override {
    jre_headless = self.jdk11_headless;
  }).overrideAttrs(_: rec {
    version = elk7Version;
    name = "elasticsearch-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "07p16n53fg513l4f04zq10hh5j9q6rjwz8hs8jj8y97jynvf6yiv";
    };
  });

  elasticsearch7-oss = (super.elasticsearch7-oss.override {
    jre_headless = self.jdk11_headless;
  }).overrideAttrs(_: rec {
    version = elk7Version;
    name = "elasticsearch-oss-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "1m6wpxs56qb6n473hawfw2n8nny8gj3dy8glq4x05005aa8dv6kh";
    };
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

  graylog = super.graylog.overrideAttrs(_: rec {
    version = "3.3.16";

    src = fetchurl {
      url = "https://packages.graylog2.org/releases/graylog/graylog-${version}.tgz";
      sha256 = "17nxvj6haf5an6yj6zdjvcaxlliamcl16bca1z1jjcd7h9yjgxrz";
    };
  });

  grub2_full = super.callPackage ./grub/2.0x.nix { };

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
  });

  kibana7-oss = super.kibana7-oss.overrideAttrs(_: rec {
    version = elk7Version;
    name = "kibana-oss-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/kibana/${name}-linux-x86_64.tar.gz";
      sha256 = "050rhx82rqpgqssp1rdflz1ska3f179kd2k2xznb39614nk0m6gs";
    };
  });

  inherit (super.callPackages ./matomo {})
    matomo
    matomo-beta;

  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };
  kubernetes-dashboard-metrics-scraper = super.callPackage ./kubernetes-dashboard-metrics-scraper.nix { };

  auditbeat7 = self.filebeat7.overrideAttrs(a: a // {
    name = "auditbeat-${a.version}";

    subPackages = [
      "auditbeat"
    ];
  });
  filebeat7 = super.filebeat7.overrideAttrs(a: a // {
    patches = [
      # upstream: Fix nil panic when overwriting metadata (#24741)
      # released in v8.0.0-alpha1
      ./filebeat-fix-events.patch
    ];
  });

  # Import old php versions from nix-phps
  # NOTE: php7.3 is already removed on unstable
  inherit (phps) php56;
  inherit (phps) php72;

  # Those are specialised packages for "direct consumption" use in our LAMP roles.

  lamp_php56 = self.php56.withExtensions ({ enabled, all }:
              enabled ++ [
                all.bcmath
                all.imagick
                all.memcached
                all.redis
              ]);

  lamp_php72 = self.php72.withExtensions ({ enabled, all }:
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


  matrix-synapse = super.matrix-synapse.overrideAttrs(orig: rec {
    pname = "matrix-synapse";
    version = "1.47.1";
    name = "${pname}-${version}";

    src = super.python3Packages.fetchPypi {
      inherit pname version;
      sha256 = "17l4cq2295lwm35zy6bm6ljqd2f6mlgc14q8g9p9s58s4gikbncm";
    };
  });

  mc = super.callPackage ./mc.nix { };

  mongodb-3_6 = super.mongodb-3_6.overrideAttrs(_: rec {
    # We have set the license to null to avoid that Hydra complains about unfree
    # licenses (here: SSPL). We should explicitly allow SSPL in the future and
    # remove this override here.
    meta.license = null;
    version = "3.6.19";
    name = "mongodb-${version}";
    src = super.fetchurl {
      url = "https://fastdl.mongodb.org/src/mongodb-src-r${version}.tar.gz";
      sha256 = "0y0k5lc2czvg8zirvqfnmpv9z0xz2slp2zfacp0hm0kzcnq82m51";
    };
  });
  mongodb-4_0 = super.mongodb-4_0.overrideAttrs(_: rec {
    # We have set the license to null to avoid that Hydra complains about unfree
    # licenses (here: SSPL). We should explicitly allow SSPL in the future and
    # remove this override here.
    meta.license = null;
    version = "4.0.19";
    name = "mongodb-${version}";
    src = super.fetchurl {
      url = "https://fastdl.mongodb.org/src/mongodb-src-r${version}.tar.gz";
      sha256 = "1kbw8vjbwlh94y58am0cxdz92mpb4amf575x0p456h1k3kh87rjg";
    };
  });
  mongodb-4_2 = super.mongodb-4_2.overrideAttrs(_: rec {
    # We have set the license to null to avoid that Hydra complains about unfree
    # licenses (here: SSPL). We should explicitly allow SSPL in the future and
    # remove this override here.
    meta.license = null;
    version = "4.2.18";
    name = "mongodb-${version}";
    src = super.fetchurl {
      url = "https://fastdl.mongodb.org/src/mongodb-src-r${version}.tar.gz";
      sha256 = "1fl555n8nnp3qpgx2hppz6yjh9w697kryzgkv73qld8zrikrbfsv";
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


  polkit = super.polkit.overrideAttrs(_: {

    patches = [
      # Don't use etc/dbus-1/system.d
      # Upstream MR: https://gitlab.freedesktop.org/polkit/polkit/merge_requests/11
      (fetchpatch {
        url = "https://gitlab.freedesktop.org/polkit/polkit/commit/5dd4e22efd05d55833c4634b56e473812b5acbf2.patch";
        sha256 = "17lv7xj5ksa27iv4zpm4zwd4iy8zbwjj4ximslfq3sasiz9kxhlp";
      })
      (fetchpatch {
        # https://www.openwall.com/lists/oss-security/2021/06/03/1
        # https://gitlab.freedesktop.org/polkit/polkit/-/merge_requests/79
        name = "CVE-2021-3560.patch";
        url = "https://gitlab.freedesktop.org/polkit/polkit/-/commit/a04d13affe0fa53ff618e07aa8f57f4c0e3b9b81.patch";
        sha256 = "157ddsizgr290jsb8fpafrc37gc1qw5pdvl351vnn3pzhqs7n6f4";
      })
      # pkexec: local privilege escalation (CVE-2021-4034)
      (fetchpatch {
        url = "https://gitlab.freedesktop.org/polkit/polkit/-/commit/a2bf5c9c83b6ae46cbd5c779d3055bff81ded683.patch";
        sha256 = "162jkpg2myq0rb0s5k3nfr4pqwv9im13jf6vzj8p5l39nazg5i4s";
      })
    ];
  });

  postgis_2_5 = super.postgis.overrideAttrs(_: rec {
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
      cheroot = thisPy.pkgs.callPackage ./python/cheroot { };
      cherrypy = thisPy.pkgs.callPackage ./python/cherrypy { };
      cython = thisPy.pkgs.callPackage ./python/Cython { };
      jaraco_text = thisPy.pkgs.callPackage ./python/jaraco_text { };
      PasteDeploy = python-super.PasteDeploy.overrideAttrs (oldattrs: {
        # for pkg_resources
        propagatedBuildInputs = oldattrs.propagatedBuildInputs ++ [python-self.setuptools];
      });
      pecan = thisPy.pkgs.callPackage ./python/pecan { };
      portend = thisPy.pkgs.callPackage ./python/portend { };
      pypytools = thisPy.pkgs.callPackage ./python/pypytools { };
      pyquery = thisPy.pkgs.callPackage ./python/pyquery { };
      routes = python-super.routes.overrideAttrs (oldattrs: {
        # work around a weird pythonImportsCheck failure
        #buildInputs = oldattrs.propagatedBuildInputs;
        #pythonImportsCheck = [];
        pythonImportsCheckPhase = ''
        #  set -x
        #  export PYTHONPATH=$out/${self.python27.sitePackages}:$PYTHONPATH
        #  python -v -c "import routes"
        '';
      });
      tempora = thisPy.pkgs.callPackage ./python/tempora { };
      waitress = thisPy.pkgs.callPackage ./python/waitress { };
      webtest = thisPy.pkgs.callPackage ./python/webtest {
        pastedeploy = python-self.PasteDeploy;
      };
      WebTest = python-self.webtest;
      zc_lockfile = thisPy.pkgs.callPackage ./python/zc_lockfile { };
    };
  };

  qemu_ceph = super.qemu.override { cephSupport = true; };

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
