self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  pkgs-20_03 = import versions.nixos-20_03 {};

in {
  # keep in sync with nixos/platform/garbagecollect/default.nix
  nixpkgs-20_03-src = versions.nixos-20_03;

  #
  # == our own stuff
  #
  fc = (import ./default.nix {
    pkgs = self;
    inherit pkgs-20_03;
  });

  #
  # imports from other nixpkgs versions
  #
  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });

  certmgr = super.callPackage ./certmgr.nix { inherit (pkgs-20_03) buildGoPackage; };
  cfssl = super.callPackage ./cfssl.nix { inherit (pkgs-20_03) buildGoPackage; };

  docsplit = super.callPackage ./docsplit { };
  inherit (pkgs-20_03) grafana;
  grub2_full = super.callPackage ./grub/2.0x.nix { };

  linux_4_19 = super.linux_4_19.override {
    argsOverride = rec {
      src = super.fetchurl {
            url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
            sha256 = "0rvlz94mjl7ygpmhz0yn2whx9dq9fmy0w1472bj16hkwbaki0an6";
      };
      version = "4.19.94";
      modDirVersion = "4.19.94";
      };
  };

  influxdb = super.callPackage ./influxdb { };
  innotop = super.callPackage ./percona/innotop.nix { };

  inherit (pkgs-20_03) kubernetes;

  libpcap_1_8 = super.callPackage ./libpcap-1.8.nix { };

  mailx = super.callPackage ./mailx.nix { };
  mc = super.callPackage ./mc.nix { };
  mongodb_3_2 = super.callPackage ./mongodb/3.2.nix {
    sasl = super.cyrus_sasl;
    boost = super.boost160;
    # 3.2 is too old for the current libpcap version 1.9, use 1.8.1
    libpcap = self.libpcap_1_8;
  };
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

  inherit (pkgs-20_03) prometheus;
  prometheus-elasticsearch-exporter = super.callPackage ./prometheus-elasticsearch-exporter.nix { };

  rabbitmq-server_3_6_5 = super.callPackage ./rabbitmq-server/3.6.5.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_6_15 = super.callPackage ./rabbitmq-server/3.6.15.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_7 = super.rabbitmq-server;
  rabbitmq-server_3_8 = pkgs-20_03.rabbitmq-server;

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

  xtrabackup = super.callPackage ./percona/xtrabackup.nix {
    inherit (self) percona;
    boost = self.boost169;
  };

  # === Python ===

  python = super.python.override {
    packageOverrides = import ./overlay-python.nix super;
  };

  python3 = super.python3.override {
    packageOverrides = import ./overlay-python.nix super;
  };

  python37 = super.python37.override {
    packageOverrides = import ./overlay-python.nix super;
  };

}
