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
  coturn = callTest ./coturn.nix {};
  docker = callTest (nixpkgs + /nixos/tests/docker.nix) {};
  elasticsearch6 = callTest ./elasticsearch.nix { version = "6"; };
  elasticsearch7 = callTest ./elasticsearch.nix { version = "7"; };
  fcagent = callTest ./fcagent.nix {};
  ffmpeg = callTest ./ffmpeg.nix {};
  garbagecollect = callTest ./garbagecollect.nix {};
  graylog = callTest ./graylog.nix {};
  haproxy = callTest ./haproxy.nix {};
  journal = callTest ./journal.nix {};
  kibana6 = callTest ./kibana.nix { version = "6"; };
  kibana7 = callTest ./kibana.nix { version = "7"; };
  kubernetes = callTest ./kubernetes {};
  lamp = callTest ./lamp.nix {};
  login = callTest ./login.nix {};
  logrotate = callTest ./logrotate.nix {};
  mail = callTest ./mail {};
  mailstub = callTest ./mail/stub.nix {};
  memcached = callTest ./memcached.nix {};
  mongodb34 = callTest ./mongodb.nix { version = "3.4"; };
  mongodb36 = callTest ./mongodb.nix { version = "3.6"; };
  mongodb40 = callTest ./mongodb.nix { version = "4.0"; };
  mysql57 = callTest ./mysql.nix { rolename = "mysql57"; };
  network = callSubTests ./network {};
  nfs = callTest ./nfs.nix {};
  nginx = callTest ./nginx.nix {};
  openvpn = callTest ./openvpn.nix {};
  percona80 = callTest ./mysql.nix { rolename = "percona80"; };
  postgresql10 = callTest ./postgresql.nix { rolename = "postgresql10"; };
  postgresql11 = callTest ./postgresql.nix { rolename = "postgresql11"; };
  postgresql12 = callTest ./postgresql.nix { rolename = "postgresql12"; };
  postgresql96 = callTest ./postgresql.nix { rolename = "postgresql96"; };
  prometheus = callTest ./prometheus.nix {};
  rabbitmq36_15 = callTest ./rabbitmq.nix { rolename = "rabbitmq36_15"; };
  rabbitmq36_5 = callTest ./rabbitmq.nix { rolename = "rabbitmq36_5"; };
  rabbitmq37 = callTest ./rabbitmq.nix { rolename = "rabbitmq37"; };
  rabbitmq38 = callTest ./rabbitmq.nix { rolename = "rabbitmq38"; };
  redis = callTest ./redis.nix {};
  rg-relay = callTest ./statshost/rg-relay.nix {};
  sensu = callTest ./sensu.nix {};
  statshost-global = callTest ./statshost/statshost-global.nix {};
  statshost-master = callTest ./statshost/statshost-master.nix {};
  sudo = callTest ./sudo.nix {};
  syslog = callSubTests ./syslog.nix {};
  systemd-service-cycles = callTest ./systemd-service-cycles.nix {};
  vxlan = callTest ./vxlan.nix {};
  webproxy = callTest ./webproxy.nix {};
  wkhtmltopdf = callTest ./wkhtmltopdf.nix {};
}
