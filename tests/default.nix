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
  # run upstream tests against our overlay
  inherit (pkgs.nixosTests)
    matomo;

  antivirus = callTest ./antivirus.nix {};
  # seems to run but fails to find the output: "Failed to find matching auditbeat line"
  # audit = callTest ./audit.nix {};
  channel = callTest ./channel.nix {};
  coturn = callTest ./coturn.nix {};
  devhost = callTest ./devhost.nix {};
  docker = callTest (nixpkgs + /nixos/tests/docker.nix) {};
  elasticsearch6 = callTest ./elasticsearch.nix { version = "6"; };
  elasticsearch7 = callTest ./elasticsearch.nix { version = "7"; };
  fcagent = callTest ./fcagent.nix {};
  ffmpeg = callTest ./ffmpeg.nix {};
  filebeat = callTest ./filebeat.nix {};
  # fails checking the gc root, but fc-userscan seems to work on a real VM
  #garbagecollect = callTest ./garbagecollect.nix {};
  gitlab = callTest ./gitlab.nix {};

  graylog = callTest ./graylog.nix {};
  haproxy = callTest ./haproxy.nix {};
  journal = callTest ./journal.nix {};
  kernelconfig = callTest ./kernelconfig.nix {};
  kibana6 = callTest ./kibana.nix { version = "6"; };
  kibana7 = callTest ./kibana.nix { version = "7"; };
  # fails, untested on a real VM
  #k3s = callTest ./k3s {};

  lamp = callTest ./lamp.nix { };
  lamp73 = callTest ./lamp.nix { version = "lamp_php73"; };
  lamp73_tideways = callTest ./lamp.nix { version = "lamp_php73"; tideways = "1234"; };
  lamp74 = callTest ./lamp.nix { version = "lamp_php74"; };
  lamp74_tideways = callTest ./lamp.nix { version = "lamp_php74"; tideways = "1234"; };
  lamp80 = callTest ./lamp.nix { version = "lamp_php80"; };
  lamp80_tideways = callTest ./lamp.nix { version = "lamp_php80"; tideways = "1234"; };

  locale = callTest ./locale.nix {};
  login = callTest ./login.nix {};
  logging = callTest ./logging.nix {};
  logrotate = callTest ./logrotate.nix {};
  mail = callTest ./mail {};
  mailstub = callTest ./mail/stub.nix {};
  memcached = callTest ./memcached.nix {};
  mongodb34 = callTest ./mongodb.nix { version = "3.4"; };
  mongodb36 = callTest ./mongodb.nix { version = "3.6"; };
  mongodb40 = callTest ./mongodb.nix { version = "4.0"; };
  mongodb42 = callTest ./mongodb.nix { version = "4.2"; };
  mysql57 = callTest ./mysql.nix { rolename = "mysql57"; };
  network = callSubTests ./network {};
  nfs = callTest ./nfs.nix {};
  nginx = callTest ./nginx.nix {};
  openvpn = callTest ./openvpn.nix {};
  percona80 = callTest ./mysql.nix { rolename = "percona80"; };
  physical-installer = callTest ./physical-installer.nix { inherit nixpkgs; };
  postgresql10 = callTest ./postgresql.nix { rolename = "postgresql10"; };
  postgresql11 = callTest ./postgresql.nix { rolename = "postgresql11"; };
  postgresql12 = callTest ./postgresql.nix { rolename = "postgresql12"; };
  postgresql13 = callTest ./postgresql.nix { rolename = "postgresql13"; };
  prometheus = callTest ./prometheus.nix {};
  rabbitmq = callTest ./rabbitmq.nix {};
  redis = callTest ./redis.nix {};
  rg-relay = callTest ./statshost/rg-relay.nix {};
  servicecheck = callTest ./servicecheck.nix {};
  statshost-global = callTest ./statshost/statshost-global.nix {};
  statshost-master = callTest ./statshost/statshost-master.nix {};
  # fails, looks like a problem in the test. The order of groups in the id output changed.
  #sudo = callTest ./sudo.nix {};
  systemd-service-cycles = callTest ./systemd-service-cycles.nix {};
  users = callTest ./users.nix {};
  vxlan = callTest ./vxlan.nix {};
  webproxy = callTest ./webproxy.nix {};
  wkhtmltopdf = callTest ./wkhtmltopdf.nix {};
}
