self: super:

let
  versions = import ../versions.nix { pkgs = super; };
  pkgs-18_03 = import versions.nixos-18_03 {};

in {
  #
  # == our own stuff
  #
  fc = (import ./default.nix { pkgs = self; });

  #
  # == imports from older nixpkgs ==
  #
  inherit (pkgs-18_03)
    nodejs-9_x
    php56
    php56Packages;

  bundlerSensuPlugin = super.callPackage ./sensuplugins-rb/bundler-sensu-plugin.nix { };
  busybox = super.busybox.overrideAttrs (oldAttrs: {
      meta.priority = 10;
    });
  docsplit = super.callPackage ./docsplit { };
  influxdb = super.callPackage ./influxdb { };
  innotop = super.callPackage ./percona/innotop.nix { };

  mailx = super.callPackage ./mailx.nix { };
  mc = super.callPackage ./mc.nix { };
  mongodb_3_2 = super.callPackage ./mongodb/3.2.nix {
    sasl = super.cyrus_sasl;
    boost = super.boost160;
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

  rabbitmq_server_3_6_5 = super.callPackage ./rabbitmq-server/3.6.5.nix { 
    erlang = self.erlangR18; 
  };
  rabbitmq_server_3_6_15 = super.rabbitmq_server;
  rabbitmq_server_3_7 = super.callPackage ./rabbitmq-server/3.7.nix { };

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

  # We use a (our) newer version than on upstream.
  vulnix = super.callPackage ./vulnix.nix {
    pythonPackages = self.python3Packages;
  };

}
