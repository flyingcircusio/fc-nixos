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
  # Run selected upstream tests against our overlay.
  # !!! Be careful when inheriting tests from upstream as tests
  # may not use our package overlay properly!
  # We know from the docker test that the `pkgs` argument that is passed to
  # the machine config doesn't have the overlay and the test is always running
  # the upstream version of docker, including dependencies.
  # When in doubt, it's better to write our own test or copy&paste from nixpkgs.
  inherit (pkgs.nixosTests)
    matomo;

  antivirus = callTest ./antivirus.nix {};
  audit = callTest ./audit.nix {};
  backyserver_ceph-nautilus = callTest ./backyserver.nix { clientCephRelease = "nautilus"; };
  channel = callTest ./channel.nix {};
  ceph-nautilus = callTest ./ceph-nautilus.nix {};
  coturn = callTest ./coturn.nix {};
  devhost = callTest ./devhost.nix {};
  docker = callTest ./docker.nix {};
  # Not supported on 21.05 anymore.
  # elasticsearch6 = callTest ./elasticsearch.nix { version = "6"; };
  # elasticsearch7 = callTest ./elasticsearch.nix { version = "7"; };
  fcagent = callSubTests ./fcagent.nix {};
  ffmpeg = callTest ./ffmpeg.nix {};
  filebeat = callTest ./filebeat.nix {};
  garbagecollect = callTest ./garbagecollect.nix {};
  # Not supported on 21.05 anymore.
  # gitlab = callTest ./gitlab.nix {};

  # Not supported on 21.05 anymore.
  # graylog = callTest ./graylog.nix {};
  haproxy = callTest ./haproxy.nix {};
  journal = callTest ./journal.nix {};
  kernelconfig = callTest ./kernelconfig.nix {};
  kibana6 = callTest ./kibana.nix { version = "6"; };
  kibana7 = callTest ./kibana.nix { version = "7"; };
  # Not supported on 21.05 anymore.
  # k3s = callTest ./k3s {};
  # default test
  kvm_host_ceph-nautilus-nautilus = callTest ./kvm_host_ceph-nautilus.nix {clientCephRelease = "nautilus";};
  # test with already upgraded ceph server, but client tooling remaining at luminous
  #kvm_host_ceph-nautilus-luminous = callTest ./kvm_host_ceph-nautilus.nix {clientCephRelease = "luminous";};

  lamp = callTest ./lamp.nix { };
  lamp56 = callTest ./lamp.nix { version = "lamp_php56"; };
  lamp56_fpm = callTest ./lamp.nix { version = "lamp_php56"; fpm = true; };
  lamp72 = callTest ./lamp.nix { version = "lamp_php72"; };
  lamp72_fpm = callTest ./lamp.nix { version = "lamp_php72"; fpm = true; };
  lamp73 = callTest ./lamp.nix { version = "lamp_php73"; };
  lamp73_tideways = callTest ./lamp.nix { version = "lamp_php73"; tideways = "1234"; };
  lamp73_fpm = callTest ./lamp.nix { version = "lamp_php73"; fpm = true; };
  lamp73_tideways_fpm = callTest ./lamp.nix { version = "lamp_php73"; tideways = "1234"; fpm = true; };
  lamp74 = callTest ./lamp.nix { version = "lamp_php74"; };
  lamp74_tideways = callTest ./lamp.nix { version = "lamp_php74"; tideways = "1234"; };
  lamp74_fpm = callTest ./lamp.nix { version = "lamp_php74"; fpm = true; };
  lamp74_tideways_fpm = callTest ./lamp.nix { version = "lamp_php74"; tideways = "1234"; fpm = true; };
  lamp80_fpm = callTest ./lamp.nix { version = "lamp_php80"; fpm = true; };
  lamp80_tideways_fpm = callTest ./lamp.nix { version = "lamp_php80"; tideways = "1234"; fpm = true; };

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
  postgresql96 = callTest ./postgresql.nix { version = "96"; };
  postgresql10 = callTest ./postgresql.nix { version = "10"; };
  postgresql11 = callTest ./postgresql.nix { version = "11"; };
  postgresql12 = callTest ./postgresql.nix { version = "12"; };
  postgresql13 = callTest ./postgresql.nix { version = "13"; };
  prometheus = callTest ./prometheus.nix {};
  rabbitmq = callTest ./rabbitmq.nix {};
  redis = callTest ./redis.nix {};
  rg-relay = callTest ./statshost/rg-relay.nix {};
  sensu = callTest ./sensu.nix {};
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
