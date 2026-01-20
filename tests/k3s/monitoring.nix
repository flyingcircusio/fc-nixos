import ../make-test-python.nix (
  {
    lib,
    pkgs,
    testlib,
    ...
  }:
  with builtins;

  let
    master4Fe = testlib.fcIP.fe4 1;
    master4Srv = testlib.fcIP.srv4 1;

    encServices = [
      {
        address = "k3sserver.fcio.net";
        ips = [ master4Srv ];
        service = "k3s-server-server";
        password = "xvlc";
      }
    ];

    hosts = ''
      ${master4Srv} k3sserver.fcio.net
      ${master4Fe} k3sserver.fe.test.fcio.net
    '';

  in
  {

    name = "k3s-monitoring";
    nodes = {

      master =
        { lib, ... }:
        {
          imports = [ (testlib.fcConfig { }) ];

          flyingcircus.encServices = encServices;
          flyingcircus.roles.k3s-server.enable = true;
          networking.domain = "fcio.net";
          networking.hostName = lib.mkForce "k3sserver";

          services.nginx.virtualHosts."kubernetes.test.fcio.net" = {
            enableACME = false;
            forceSSL = false;
          };

          services.telegraf.enable = true;

          users.users = {
            sensuclient = {
              isSystemUser = true;
            };
          };

          virtualisation.memorySize = 2000;
          virtualisation.diskSize = lib.mkForce 3000;

          virtualisation.vlans = [
            1
            2
          ];
          virtualisation.qemu.options = [ "-smp 2" ];
        };
    };

    testScript =
      { nodes, ... }:
      let
        masterSensuCheck = testlib.sensuCheckCmd nodes.master;
      in
      ''

        k3sserver.wait_for_unit("k3s.service")
        k3sserver.wait_until_succeeds('k3s kubectl get --raw=/healthz | grep -q ok')
        k3sserver.succeed('k3s kubectl get node k3sserver -o jsonpath=\'{.status.conditions[?(@.type=="Ready")].status}\' | grep -q True')

        # telegraf.service fails to start when the token file doesn't exist. Explicitly restart after k3s created it
        k3sserver.wait_for_file("/var/lib/k3s/tokens/telegraf")
        k3sserver.systemctl("start telegraf")

        with subtest("sensu should be able to access the API server endpoint"):
          k3sserver.wait_for_file("/var/lib/k3s/tokens/sensuclient")
          k3sserver.wait_until_succeeds("${masterSensuCheck "kube-apiserver"}")
          k3sserver.wait_until_succeeds("${masterSensuCheck "kube-nodes-ready"}")

        with subtest("telegraf should be running on server"):
          k3sserver.wait_for_unit("telegraf.service")
          k3sserver.wait_until_succeeds("curl -s -o /dev/null http://${master4Srv}:9126")
      '';
  }
)
