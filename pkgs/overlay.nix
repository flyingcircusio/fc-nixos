self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  elk7Version = "7.8.0";
  inherit (super) lib;

in {
  #
  # == our own stuff
  #
  fc = (import ./default.nix {
    pkgs = self;
  });

  #
  # imports from other nixpkgs versions
  #
  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = super.callPackage ./certmgr.nix {  };
  cfssl = super.callPackage ./cfssl.nix { };

  cgmemtime = super.callPackage ./cgmemtime.nix { };

  #docsplit = super.callPackage ./docsplit { };

  elasticsearch7 = super.elasticsearch7.overrideAttrs(_: rec {
    version = elk7Version;
    name = "elasticsearch-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "1vy3z5f3zn9a2caa9jq1w4iagqrdmd27wr51bl6yf8v74169vpr4";
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
      sha256 = "0xnh07n894f170ahawcg03jm3xk4qpjjbfwkvd955vdgihpy60gh";
    };
    meta.license = null;
  });

  kubernetes-dashboard = super.callPackage ./kubernetes-dashboard.nix { };

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

  mysql = super.mariadb;

  # This is our default version.
  nginxStable = (super.nginxStable.override {
    modules = with super.nginxModules; [
      dav
      modsecurity
      modsecurity-nginx
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
      modsecurity
      modsecurity-nginx
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

  percona57 = super.callPackage ./percona/5.7.nix { boost = self.boost159; };
  percona80 = super.callPackage ./percona/8.0.nix { boost = self.boost172; };

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
  rabbitmq-server_3_7 = super.rabbitmq-server; # XXX this is actually 3.8
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
