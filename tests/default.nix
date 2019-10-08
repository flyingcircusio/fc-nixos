{ system ? builtins.currentSystem
, nixpkgs ? (import ../versions.nix {}).nixpkgs
, pkgs ? import nixpkgs { inherit system; }
}:

with pkgs.lib;

let
  # test calling code copied from nixos/release.nix
  importTest = fn: args: system: import fn ({
    inherit system;
  } // args);

  callTest = fn: args: hydraJob (importTest fn args system);

  callSubTests = fn: args: let
    discover = attrs: let
      subTests = filterAttrs (const (hasAttr "test")) attrs;
    in mapAttrs (const (t: hydraJob t.test)) subTests;
  in discover (importTest fn args system);

in {
  fcagent = callTest ./fcagent.nix {};
  garbagecollect = callTest ./garbagecollect.nix {};
  login = callTest ./login.nix {};
  logrotate = callTest ./logrotate.nix {};
  mail = callSubTests ./mail.nix {};
  memcached = callTest ./memcached.nix {};
  mongodb32 = callTest ./mongodb.nix { rolename = "mongodb32"; };
  mongodb34 = callTest ./mongodb.nix { rolename = "mongodb34"; };
  network = callSubTests ./network {};
  mysql55 = callTest ./mysql.nix { rolename = "mysql55"; };
  mysql56 = callTest ./mysql.nix { rolename = "mysql56"; };
  mysql57 = callTest ./mysql.nix { rolename = "mysql57"; };
  nfs = callTest ./nfs.nix {};
  nginx = callTest ./nginx.nix {};
  nginx_reload = callTest (nixpkgs + /nixos/tests/nginx.nix) {};
  openvpn = callTest ./openvpn.nix {};
  percona80 = callTest ./mysql.nix { rolename = "percona80"; };
  postgresql95 = callTest ./postgresql.nix { rolename = "postgresql95"; };
  postgresql96 = callTest ./postgresql.nix { rolename = "postgresql96"; };
  postgresql10 = callTest ./postgresql.nix { rolename = "postgresql10"; };
  postgresql11 = callTest ./postgresql.nix { rolename = "postgresql11"; };
  prometheus = callTest ./prometheus.nix {};
  rabbitmq36_5 = callTest ./rabbitmq.nix { rolename = "rabbitmq36_5"; };
  rabbitmq36_15 = callTest ./rabbitmq.nix { rolename = "rabbitmq36_15"; };
  rabbitmq37 = callTest ./rabbitmq.nix { rolename = "rabbitmq37"; };
  redis = callTest ./redis.nix {};
  rg-relay = callTest ./rg-relay.nix {};
  statshost-master = callTest ./statshost-master.nix {};
  sudo = callTest ./sudo.nix {};
  syslog = callSubTests ./syslog.nix {};
  systemd-service-cycles = callTest ./systemd-service-cycles.nix {};
  vxlan = callTest ./vxlan.nix {};
  webproxy = callTest ./webproxy.nix {};
}
