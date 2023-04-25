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

  callTest = fn: args: hydraJob (importTest fn args system).test;

  callSubTests = fn: args: let
    discover = attrs: let
      subTests = filterAttrs (const (hasAttr "test")) attrs;
    in mapAttrs (const (t: hydraJob t.test)) subTests;
  in discover (importTest fn args system);

in {
  # Run selected upstream tests against our overlay.
  # !!! Be careful when inheriting tests from upstream as tests
  # may not use our package overlay properly!
  # We know from the docker test that the `pkgs` argument that is passed to
  # the machine config doesn't have the overlay and the test is always running
  # the upstream version of docker, including dependencies.
  # When in doubt, it's better to write our own test or copy&paste from nixpkgs.
  # inherit (pkgs.nixosTests)

  antivirus = callTest ./antivirus.nix {};
  audit = callTest ./audit.nix {};
  backyserver = callTest ./backyserver.nix {};
  channel = callTest ./channel.nix {};
  # XXX: ceph build failure
  # ceph = callTest ./ceph.nix {};
  coturn = callTest ./coturn.nix {};
  devhost = callTest ./devhost.nix {};
  docker = callTest ./docker.nix {};
  fcagent = callSubTests ./fcagent.nix {};
  ffmpeg = callTest ./ffmpeg.nix {};
  filebeat = callTest ./filebeat.nix {};
  collect-garbage = callTest ./collect-garbage.nix {};
  gitlab = callTest ./gitlab.nix {};
  haproxy = callTest ./haproxy.nix {};
  java = callTest ./java.nix {};
  journal = callTest ./journal.nix {};
  journalbeat = callTest ./journalbeat.nix {};
  kernelconfig = callTest ./kernelconfig.nix {};
  # k3s = callTest ./k3s {};

  lampVm = callTest ./lamp/vm-test.nix { };
  lampVm72 = callTest ./lamp/vm-test.nix { version = "lamp_php72"; };
  lampVm73 = callTest ./lamp/vm-test.nix { version = "lamp_php73"; };
  lampVm74 = callTest ./lamp/vm-test.nix { version = "lamp_php74"; };
  lampVm80 = callTest ./lamp/vm-test.nix { version = "lamp_php80"; };
  lampVm80_tideways = callTest ./lamp/vm-test.nix { version = "lamp_php80"; tideways = "1234"; };
  lampVm81 = callTest ./lamp/vm-test.nix { version = "lamp_php81"; };
  lampVm81_tideways = callTest ./lamp/vm-test.nix { version = "lamp_php81"; tideways = "1234"; };

  lampPackage74 = callTest ./lamp/package-test.nix { version = "lamp_php74"; };
  lampPackage80 = callTest ./lamp/package-test.nix { version = "lamp_php80"; };
  lampPackage81 = callTest ./lamp/package-test.nix { version = "lamp_php81"; };

  locale = callTest ./locale.nix {};
  login = callTest ./login.nix {};
  logrotate = callTest ./logrotate.nix {};
  #mail = callTest ./mail {};
  mailstub = callTest ./mail/stub.nix {};
  matomo = callTest ./matomo.nix {};
  memcached = callTest ./memcached.nix {};
  mongodb42 = callTest ./mongodb.nix { version = "4.2"; };
  #mysql57 = callTest ./mysql.nix { rolename = "mysql57"; };
  network = callSubTests ./network {};
  nfs = callTest ./nfs.nix {};
  nginx = callTest ./nginx.nix {};
  nodejs = callTest ./nodejs.nix {};
  opensearch = callTest ./opensearch.nix {};
  opensearch_dashboards = callTest ./opensearch_dashboards.nix {};
  openvpn = callTest ./openvpn.nix {};
  percona80 = callTest ./mysql.nix { rolename = "percona80"; };
  physical-installer = callTest ./physical-installer.nix { inherit nixpkgs; };
  postgresql11 = callTest ./postgresql { version = "11"; };
  postgresql12 = callTest ./postgresql { version = "12"; };
  postgresql13 = callTest ./postgresql { version = "13"; };
  postgresql14 = callTest ./postgresql { version = "14"; };
  postgresql15 = callTest ./postgresql { version = "15"; };
  postgresql-autoupgrade = callSubTests ./postgresql/upgrade.nix {};
  prometheus = callTest ./prometheus.nix {};
  rabbitmq = callTest ./rabbitmq.nix {};
  redis = callTest ./redis.nix {};
  rg-relay = callTest ./statshost/rg-relay.nix {};
  sensuclient = callTest ./sensuclient.nix {};
  servicecheck = callTest ./servicecheck.nix {};
  statshost-global = callTest ./statshost/statshost-global.nix {};
  statshost-master = callTest ./statshost/statshost-master.nix {};
  sudo = callTest ./sudo.nix {};
  syslog = callSubTests ./syslog.nix {};
  systemd-service-cycles = callTest ./systemd-service-cycles.nix {};
  users = callTest ./users.nix {};
  vxlan = callTest ./vxlan.nix {};
  webproxy = callTest ./webproxy.nix {};
  wkhtmltopdf = callTest ./wkhtmltopdf.nix {};
}
