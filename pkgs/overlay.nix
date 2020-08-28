self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  pkgs-unstable = import versions.nixos-unstable {};
  elk7Version = "7.8.0";
  inherit (super) lib;

  # Taken from nixpkgs all-packages.nix reduced to the kernel packages we need.
  linuxPackages_5_4 = super.recurseIntoAttrs
    (lib.makeExtensible (self: with self; {
        inherit (pkgs-unstable.linuxPackages_5_4) kernel virtualbox virtualboxGuestAdditions;
    }));

in {
  # keep in sync with nixos/platform/garbagecollect/default.nix
  nixpkgs-unstable-src = versions.nixos-unstable;

  #
  # == our own stuff
  #
  fc = (import ./default.nix {
    pkgs = self;
    inherit pkgs-unstable;
  });

  #
  # imports from other nixpkgs versions
  #
  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = super.callPackage ./certmgr.nix { inherit (pkgs-unstable) buildGoPackage; };
  cfssl = super.callPackage ./cfssl.nix { inherit (pkgs-unstable) buildGoPackage; };

  inherit (pkgs-unstable) coturn;

  docsplit = super.callPackage ./docsplit { };

  elasticsearch7 = pkgs-unstable.elasticsearch7.overrideAttrs(_: rec {
    version = elk7Version;
    name = "elasticsearch-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/elasticsearch/${name}-linux-x86_64.tar.gz";
      sha256 = "1vy3z5f3zn9a2caa9jq1w4iagqrdmd27wr51bl6yf8v74169vpr4";
    };
    meta.license = null;
  });

  kibana7 = pkgs-unstable.kibana7.overrideAttrs(_: rec {
    version = elk7Version;
    name = "kibana-${version}";

    src = super.fetchurl {
      url = "https://artifacts.elastic.co/downloads/kibana/${name}-linux-x86_64.tar.gz";
      sha256 = "0xnh07n894f170ahawcg03jm3xk4qpjjbfwkvd955vdgihpy60gh";
    };
    meta.license = null;
  });

  inherit (pkgs-unstable) grafana;

  grub2_full = super.callPackage ./grub/2.0x.nix { };

  inherit (pkgs-unstable) influxdb;

  innotop = super.callPackage ./percona/innotop.nix { };

  inherit (pkgs-unstable) kubernetes;

  libpcap_1_8 = super.callPackage ./libpcap-1.8.nix { };

  inherit linuxPackages_5_4;
  linuxPackages = self.linuxPackages_5_4;

  mailx = super.callPackage ./mailx.nix { };
  mc = super.callPackage ./mc.nix { };

  mongodb-3_2 = super.callPackage ./mongodb/3.2.nix {
    sasl = super.cyrus_sasl;
    boost = super.boost160;
    # 3.2 is too old for the current libpcap version 1.9, use 1.8.1
    libpcap = self.libpcap_1_8;
  };
  mongodb_3_2 = self.mongodb-3_2;
  mongodb-3_4 = super.mongodb;
  mongodb-3_6 = pkgs-unstable.mongodb-3_6.overrideAttrs(_: rec {
    meta.license = null;
    version = "3.6.19";
    name = "mongodb-${version}";
    src = super.fetchurl {
      url = "https://fastdl.mongodb.org/src/mongodb-src-r${version}.tar.gz";
      sha256 = "0y0k5lc2czvg8zirvqfnmpv9z0xz2slp2zfacp0hm0kzcnq82m51";
    };
  });
  mongodb-4_0 = pkgs-unstable.mongodb-4_0.overrideAttrs(_: rec {
    meta.license = null;
    version = "4.0.19";
    name = "mongodb-${version}";
    src = super.fetchurl {
      url = "https://fastdl.mongodb.org/src/mongodb-src-r${version}.tar.gz";
      sha256 = "1kbw8vjbwlh94y58am0cxdz92mpb4amf575x0p456h1k3kh87rjg";
    };
  });

  mysql = super.mariadb;

  nginx = super.nginx.override {
    modules = [
      self.nginxModules.dav
      self.nginxModules.modsecurity
      self.nginxModules.moreheaders
      self.nginxModules.rtmp
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
  percona80 = super.callPackage ./percona/8.0.nix { boost = self.boost169; };

  inherit (pkgs-unstable) postgresql_12;

  inherit (pkgs-unstable) prometheus;

  prometheus-elasticsearch-exporter = super.callPackage ./prometheus-elasticsearch-exporter.nix { };

  rabbitmq-server_3_6_5 = super.callPackage ./rabbitmq-server/3.6.5.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_6_15 = super.callPackage ./rabbitmq-server/3.6.15.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_7 = super.rabbitmq-server;
  rabbitmq-server_3_8 = pkgs-unstable.rabbitmq-server;

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

  inherit (pkgs-unstable) writeShellScript;

  xtrabackup = super.callPackage ./percona/xtrabackup.nix {
    inherit (self) percona;
    boost = self.boost169;
  };

  # === Python ===

  # python2
  python27 = super.python27.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python27Packages = self.python27.pkgs;

  python35 = super.python35.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python35Packages = self.python35.pkgs;

  python36 = super.python36.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python36Packages = self.python36.pkgs;

  python37 = super.python37.override {
    packageOverrides = import ./overlay-python.nix super;
  };
  python37Packages = self.python37.pkgs;

}
