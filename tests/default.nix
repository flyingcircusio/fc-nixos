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
  antivirus = callTest ./antivirus.nix {};
  docker = callTest (nixpkgs + /nixos/tests/docker.nix) {};
  elasticsearch5 = callTest ./elasticsearch.nix { version = "5"; };
  elasticsearch6 = callTest ./elasticsearch.nix { version = "6"; };
  elasticsearch7 = callTest ./elasticsearch.nix { version = "7"; };
  fcagent = callTest ./fcagent.nix {};
  garbagecollect = callTest ./garbagecollect.nix {};
  graylog = callTest ./graylog.nix {};
  haproxy = callTest ./haproxy.nix {};
  journal = callTest ./journal.nix {};
  kibana6 = callTest ./kibana.nix { version = "6"; };
  kibana7 = callTest ./kibana.nix { version = "7"; };
  kubernetes = callTest ./kubernetes {};
  login = callTest ./login.nix {};
  logrotate = callTest ./logrotate.nix {};
  mail = callTest ./mail {};
  memcached = callTest ./memcached.nix {};
  mongodb32 = callTest ./mongodb.nix { rolename = "mongodb32"; };
  mongodb34 = callTest ./mongodb.nix { rolename = "mongodb34"; };
  mysql55 = callTest ./mysql.nix { rolename = "mysql55"; };
  mysql56 = callTest ./mysql.nix { rolename = "mysql56"; };
  mysql57 = callTest ./mysql.nix { rolename = "mysql57"; };
  network = callSubTests ./network {};
  nfs = callTest ./nfs.nix {};
  nginx = callTest ./nginx.nix {};
  nginx_reload = callTest (nixpkgs + /nixos/tests/nginx.nix) {};
  openvpn = callTest ./openvpn.nix {};
  percona80 = callTest ./mysql.nix { rolename = "percona80"; };
  postgresql10 = callTest ./postgresql.nix { rolename = "postgresql10"; };
  postgresql11 = callTest ./postgresql.nix { rolename = "postgresql11"; };
  postgresql95 = callTest ./postgresql.nix { rolename = "postgresql95"; };
  postgresql96 = callTest ./postgresql.nix { rolename = "postgresql96"; };
  prometheus = callTest ./prometheus.nix {};
  rabbitmq36_15 = callTest ./rabbitmq.nix { rolename = "rabbitmq36_15"; };
  rabbitmq36_5 = callTest ./rabbitmq.nix { rolename = "rabbitmq36_5"; };
  rabbitmq37 = callTest ./rabbitmq.nix { rolename = "rabbitmq37"; };
  rabbitmq38 = callTest ./rabbitmq.nix { rolename = "rabbitmq38"; };
  redis = callTest ./redis.nix {};
  rg-relay = callTest ./statshost/rg-relay.nix {};
  statshost-global = callTest ./statshost/statshost-global.nix {};
  statshost-master = callTest ./statshost/statshost-master.nix {};
  sudo = callTest ./sudo.nix {};
  syslog = callSubTests ./syslog.nix {};
  systemd-service-cycles = callTest ./systemd-service-cycles.nix {};
  vxlan = callTest ./vxlan.nix {};
  webproxy = callTest ./webproxy.nix {};
}
