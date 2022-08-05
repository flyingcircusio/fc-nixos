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
  audit = callTest ./audit.nix {};
  backyserver = callTest ./backyserver.nix {};
  channel = callTest ./channel.nix {};
  # XXX: ceph build failure
  # ceph = callTest ./ceph.nix {};
  coturn = callTest ./coturn.nix {};
  devhost = callTest ./devhost.nix {};
  docker = callTest (nixpkgs + /nixos/tests/docker.nix) {};
  elasticsearch6 = callSubTests ./elasticsearch.nix { version = "6"; };
  elasticsearch7 = callSubTests ./elasticsearch.nix { version = "7"; };
  fcagent = callSubTests ./fcagent.nix {};
  ffmpeg = callTest ./ffmpeg.nix {};
  filebeat = callTest ./filebeat.nix {};
  garbagecollect = callTest ./garbagecollect.nix {};
  gitlab = callTest ./gitlab.nix {};

  graylog = callTest ./graylog.nix {};
  haproxy = callTest ./haproxy.nix {};
  java = callTest ./java.nix {};
  journal = callTest ./journal.nix {};
  kernelconfig = callTest ./kernelconfig.nix {};
  kibana6 = callTest ./kibana.nix { version = "6"; };
  kibana7 = callTest ./kibana.nix { version = "7"; };
  k3s = callTest ./k3s {};

  lampVm = callTest ./lamp/vm-test.nix { };
  lampVm72 = callTest ./lamp/vm-test.nix { version = "lamp_php72"; };
  lampVm73 = callTest ./lamp/vm-test.nix { version = "lamp_php73"; };
  lampVm73_tideways = callTest ./lamp/vm-test.nix { version = "lamp_php73"; tideways = "1234"; };
  lampVm74 = callTest ./lamp/vm-test.nix { version = "lamp_php74"; };
  lampVm74_tideways = callTest ./lamp/vm-test.nix { version = "lamp_php74"; tideways = "1234"; };
  lampVm80 = callTest ./lamp/vm-test.nix { version = "lamp_php80"; };

  # lampPackage = callTest ./lamp/package-test.nix { };
  # lampPackage72 = callTest ./lamp/package-test.nix { version = "lamp_php72"; };
  # lampPackage73 = callTest ./lamp/package-test.nix { version = "lamp_php73"; };
  # regression test for PL-130643 only starts at lamp_php74
  lampPackage74 = callTest ./lamp/package-test.nix { version = "lamp_php74"; };
  lampPackage80 = callTest ./lamp/package-test.nix { version = "lamp_php80"; };


  # currently not supported: PL-130612
  # lamp80_tideways = callTest ./lamp/vmTest.nix { version = "lamp_php80"; tideways = "1234"; };

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
  postgresql14 = callTest ./postgresql.nix { rolename = "postgresql14"; };
  prometheus = callTest ./prometheus.nix {};
  rabbitmq = callTest ./rabbitmq.nix {};
  redis = callTest ./redis.nix {};
  rg-relay = callTest ./statshost/rg-relay.nix {};
  sensuclient = callTest ./sensuclient.nix {};
  servicecheck = callTest ./servicecheck.nix {};
  statshost-global = callTest ./statshost/statshost-global.nix {};
  statshost-master = callTest ./statshost/statshost-master.nix {};
  sudo = callTest ./sudo.nix {};
  systemd-service-cycles = callTest ./systemd-service-cycles.nix {};
  users = callTest ./users.nix {};
  vxlan = callTest ./vxlan.nix {};
  webproxy = callTest ./webproxy.nix {};
  wkhtmltopdf = callTest ./wkhtmltopdf.nix {};
}
