{
  system ? builtins.currentSystem,
  nixpkgs ? (import ../release/versions.nix { }).nixpkgs,
  pkgs ? import nixpkgs { inherit system; },
}:

with pkgs.lib;

let
  # test calling code copied from nixos/release.nix
  importTest =
    fn: args: system:
    import fn (
      {
        inherit system;
      }
      // args
    );

  callTest = fn: args: importTest fn args system;

  callSubTests = callTest;

in
{
  # Run selected upstream tests against our overlay.
  # !!! Be careful when inheriting tests from upstream as tests
  # may not use our package overlay properly!
  # We know from the docker test that the `pkgs` argument that is passed to
  # the machine config doesn't have the overlay and the test is always running
  # the upstream version of docker, including dependencies.
  # When in doubt, it's better to write our own test or copy&paste from nixpkgs.
  # inherit (pkgs.nixosTests)

  skvaider = callTest ./skvaider.nix { };
  alloy = callTest ./alloy.nix { };
  antivirus = callTest ./antivirus.nix { };
  audit = callTest ./audit.nix { };
  backyserver_ceph-nautilus = callTest ./backyserver.nix { clientCephRelease = "nautilus"; };
  backyserver_volumes = callTest ./backy_volumes.nix { };
  channel = callTest ./channel.nix { };
  ceph-nautilus = callTest ./ceph-nautilus.nix { };
  ceph-pacific = callTest ./ceph-pacific.nix { };
  coturn = callTest ./coturn.nix { };
  docker = callTest ./docker.nix { };
  fcagent = callTest ./fcagent.nix { };
  fde-tooling = callTest ./fde-tooling.nix { };
  ferretdb = callTest ./ferretdb.nix { };
  ffmpeg = callTest ./ffmpeg.nix { };
  filebeat = callTest ./filebeat.nix { };
  frr = callSubTests ./frr.nix { };
  collect-garbage = callTest ./collect-garbage.nix { };
  gitlab = callTest ./gitlab.nix { };
  haproxy = callTest ./haproxy.nix { };
  initrd = callTest ./initrd.nix { };
  ip-forward = callTest ./ip-forward.nix { };
  ipv6-autoconfig = callSubTests ./ipv6-autoconfig.nix { };
  java = callTest ./java.nix { };
  journal = callTest ./journal.nix { };
  journalbeat = callTest ./journalbeat.nix { };
  k3s = callTest ./k3s { };
  k3s_ipv6 = callTest ./k3s { enableIPv6 = true; };
  k3s_monitoring = callTest ./k3s/monitoring.nix { };
  kernelconfig = callTest ./kernelconfig.nix { };
  kernelversions = callTest ./kernelversions.nix { };
  kvm_host_ceph-nautilus-nautilus = callTest ./kvm_host_ceph-nautilus.nix {
    clientCephRelease = "nautilus";
    serverCephRelease = "nautilus";
  };
  kvm_host_ceph-nautilus-pacific = callTest ./kvm_host_ceph-nautilus.nix {
    clientCephRelease = "nautilus";
    serverCephRelease = "pacific";
  };
  kvm_host_ceph-pacific-pacific = callTest ./kvm_host_ceph-nautilus.nix {
    clientCephRelease = "pacific";
    serverCephRelease = "pacific";
  };
  lampVm = callTest ./lamp/vm-test.nix { };
  lampVm72 = callTest ./lamp/vm-test.nix { version = "lamp_php72"; };
  lampVm73 = callTest ./lamp/vm-test.nix { version = "lamp_php73"; };
  lampVm74 = callTest ./lamp/vm-test.nix { version = "lamp_php74"; };
  lampVm80 = callTest ./lamp/vm-test.nix { version = "lamp_php80"; };
  lampVm81 = callTest ./lamp/vm-test.nix { version = "lamp_php81"; };
  lampVm82 = callTest ./lamp/vm-test.nix { version = "lamp_php82"; };
  lampVm83 = callTest ./lamp/vm-test.nix { version = "lamp_php83"; };
  lampVm84 = callTest ./lamp/vm-test.nix { version = "lamp_php84"; };
  lampVm85 = callTest ./lamp/vm-test.nix { version = "lamp_php85"; };

  locale = callTest ./locale.nix { };
  loki = callTest ./loki.nix { };
  loki-relay = callTest ./loki-relay.nix { };
  loghost = callTest ./loghost.nix { };
  login = callTest ./login.nix { };
  logrotate = callTest ./logrotate.nix { };
  mail = callTest ./mail { };
  mailstub = callTest ./mail/stub.nix { };
  matomo = callTest ./matomo.nix { };
  mariadb = callTest ./mariadb.nix { };
  memcached = callTest ./memcached.nix { };
  mongodb32 = callTest ./mongodb.nix { version = "3.2"; };
  mongodb34 = callTest ./mongodb.nix { version = "3.4"; };
  mongodb36 = callTest ./mongodb.nix { version = "3.6"; };
  mongodb40 = callTest ./mongodb.nix { version = "4.0"; };
  mongodb42 = callTest ./mongodb.nix { version = "4.2"; };
  mongodb70 = callTest ./mongodb.nix { version = "7.0"; };
  mongodb80 = callTest ./mongodb.nix { version = "8.0"; };
  network = callSubTests ./network { };
  nfs = callSubTests ./nfs.nix { };
  nginx = callTest ./nginx.nix { };
  nix-version = callTest ./nix-version.nix { };
  nodejs = callTest ./nodejs.nix { };
  opensearch = callTest ./opensearch.nix { };
  opensearch_dashboards = callTest ./opensearch_dashboards.nix { };
  openvpn = callTest ./openvpn.nix { };
  open-webui = callTest ./open-webui.nix { };
  percona84 = callTest ./mysql.nix { rolename = "percona84"; };
  physical-installer = callTest ./physical-installer.nix { inherit nixpkgs; };
  postgresql14 = callTest ./postgresql { version = "14"; };
  postgresql15 = callTest ./postgresql { version = "15"; };
  postgresql16 = callTest ./postgresql { version = "16"; };
  postgresql17 = callTest ./postgresql { version = "17"; };
  postgresql18 = callTest ./postgresql { version = "18"; };
  postgresql-autoupgrade = callSubTests ./postgresql/upgrade.nix { };
  postgresql-autoupgrade-exts = callSubTests ./postgresql/upgrade-with-extension.nix { };
  prometheus = callTest ./prometheus.nix { };
  rabbitmq = callTest ./rabbitmq.nix { };
  redis = callTest ./redis.nix { };
  rg-relay = callTest ./statshost/rg-relay.nix { };
  router = callSubTests ./router { };
  sensuclient = callTest ./sensuclient.nix { };
  servicecheck = callTest ./servicecheck.nix { };
  statshost-global = callTest ./statshost/statshost-global.nix { };
  statshost-master = callTest ./statshost/statshost-master.nix { };
  sudo = callTest ./sudo.nix { };
  syslog = callSubTests ./syslog.nix { };
  systemd-service-cycles = callTest ./systemd-service-cycles.nix { };
  users = callTest ./users.nix { };
  vxlan = callTest ./vxlan.nix { };
  webproxy = callTest ./webproxy.nix { };
  webproxy-legacy = callTest ./webproxy-legacy.nix { };
}
