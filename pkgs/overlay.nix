self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  pkgs-18_09 = import versions.nixos-18_09 {};
  pkgs-19_09 = import versions.nixos-19_09 {};

in {
  #
  # == our own stuff
  #
  fc = (import ./default.nix { pkgs = self; inherit pkgs-19_09; });

  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });
  docsplit = super.callPackage ./docsplit { };

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

  mailx = super.callPackage ./mailx.nix { };
  mc = super.callPackage ./mc.nix { };
  mongodb_3_2 = super.callPackage ./mongodb/3.2.nix {
    sasl = super.cyrus_sasl;
    boost = super.boost160;
    # 3.2 is too old for the current libpcap version 1.9, use 1.8.1
    inherit (pkgs-18_09) libpcap;
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

  prometheus-elasticsearch-exporter = super.callPackage ./prometheus-elasticsearch-exporter.nix { };
  qpress = super.callPackage ./percona/qpress.nix { };

  rabbitmq-server_3_6_5 = super.callPackage ./rabbitmq-server/3.6.5.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_6_15 = super.callPackage ./rabbitmq-server/3.6.15.nix {
    erlang = self.erlangR19;
  };
  rabbitmq-server_3_7 = super.rabbitmq-server;

  remarshal = super.callPackage ./remarshal.nix { };
  rum = super.callPackage ./postgresql/rum { };

  sensu-plugins-elasticsearch = super.callPackage ./sensuplugins-rb/sensu-plugins-elasticsearch { };
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

  vulnix = super.callPackage ./vulnix.nix { };

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
