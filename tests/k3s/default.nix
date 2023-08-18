import ../make-test-python.nix ({ lib, pkgs, testlib, ... }:
with builtins;

let

  images = map pkgs.dockerTools.pullImage (import ./airgapped-k3s-images.nix);

  net4Srv = "10.0.1";
  frontendSrv = net4Srv + ".1";
  masterSrv = net4Srv + ".2";
  nodeSrvA = net4Srv + ".3";
  nodeSrvB = net4Srv + ".4";

  net4Fe = "10.0.2";
  frontendFe = net4Fe + ".1";
  masterFe = net4Fe + ".2";

  encServices = [
    {
      address = "k3sserver.fcio.net";
      ips = [ masterSrv ];
      service = "k3s-server-server";
      password = "xvlc";
    }
    {
      address = "k3snodeA.fcio.net";
      ips = [ nodeSrvA ];
      service = "k3s-node";
    }
    {
      address = "k3snodeB.fcio.net";
      ips = [ nodeSrvB ];
      service = "k3s-node";
    }
    {
      address = "frontend.fcio.net";
      ips = [ frontendFe ];
      service = "k3s-frontend";
    }
  ];

  hosts = ''
    ${masterSrv} k3sserver.fcio.net
    ${nodeSrvA} k3snodeA.fcio.net
    ${nodeSrvB} k3snodeB.fcio.net
    ${frontendFe} frontend.fcio.net
    ${masterFe} k3sserver.fe.test.fcio.net
    ${masterFe} k3s.test.fcio.net
  '';

  redis = import ./redis.nix { inherit pkgs; };

in {

  name = "k3s";
  nodes = {

    master =
      { lib, ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];

        config = {

        flyingcircus.enc.parameters = {
          location = "test";
          resource_group = "test";
          interfaces.srv = {
            bridged = false;
            mac = "52:54:00:12:01:02";
            networks = {
              "${net4Srv}.0/24" = [ masterSrv ];
            };
            gateways = { "${net4Srv}.0/24" = "${net4Srv}.254"; };
          };
          interfaces.fe = {
            bridged = false;
            mac = "52:54:00:12:02:02";
            networks = {
              "${net4Fe}.0/24" = [ masterFe ];
            };
            gateways = {};
          };
        };
        flyingcircus.encServices = encServices;
        flyingcircus.roles.k3s-server.enable = true;
        networking.domain = "fcio.net";
        networking.hostName = lib.mkForce "k3sserver";
        networking.extraHosts = hosts;

        networking.firewall.allowedTCPPorts = [ 8888 6443 ];
        networking.firewall.allowedUDPPorts = [ 53 ];

        services.nginx.virtualHosts."acme.kubernetes.test.fcio.net" = {
          enableACME = false;
        };

        users.groups = {
          sudo-srv = {};
        };
        users.users = {
          sensuclient = { isSystemUser = true; };
        };

        flyingcircus.users.userData = [
          {
            id = 1001;
            uid = "test";
            name = "test";
            permissions = { test = [ "sudo-srv" ]; };
            password = "";
            home_directory = "/home/test";
            login_shell = "/bin/bash";
            class = "human";
          }
        ];

        virtualisation.memorySize = 2000;
        virtualisation.diskSize = lib.mkForce 3000;
        virtualisation.vlans = [ 1 2 ];
        virtualisation.qemu.options = [ "-smp 2" ];
        };
      };

    nodeA =
      { ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];

        config = {
        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            bridged = false;
            mac = "52:54:00:12:01:03";
            networks = {
              "${net4Srv}.0/24" = [ nodeSrvA ];
            };
            gateways = { "${net4Srv}.0/24" = "${net4Srv}.254"; };
          };
        };
        flyingcircus.encServices = encServices;
        flyingcircus.roles.k3s-agent.enable = true;

        networking.domain = "fcio.net";
        networking.extraHosts = hosts;
        networking.hostName = lib.mkForce "k3snodeA";
        networking.nameservers = [ "127.0.0.1" ];
        virtualisation.memorySize = 2000;
        virtualisation.diskSize = 3000;
        virtualisation.vlans = [ 1 ];
        };
      };

    nodeB =
      { ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];



        config = {
        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            bridged = false;
            mac = "52:54:00:12:01:04";
            networks = {
              "${net4Srv}.0/24" = [ nodeSrvB ];
            };
            gateways = { "${net4Srv}.0/24" = "${net4Srv}.254"; };
          };
        };
        flyingcircus.encServices = encServices;
        flyingcircus.roles.k3s-agent.enable = true;

        networking.domain = "fcio.net";
        networking.extraHosts = hosts;
        networking.hostName = lib.mkForce "k3snodeB";
        virtualisation.memorySize = 2000;
        virtualisation.diskSize = 3000;
        virtualisation.vlans = [ 1 ];
        };
      };

    frontend =
      { ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];

        flyingcircus.roles.webgateway.enable = true;
        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            bridged = false;
            mac = "52:54:00:12:01:01";
            networks = {
              "${net4Srv}.0/24" = [ frontendSrv ];
            };
            gateways = {};
          };
          interfaces.fe = {
            bridged = false;
            mac = "52:54:00:12:02:01";
            networks = {
              "${net4Fe}.0/24" = [ frontendFe ];
            };
            gateways = {};
          };
        };
        networking.domain = "fcio.net";
        networking.extraHosts = hosts;
        flyingcircus.encServices = encServices;
        virtualisation.vlans = [ 1 2 ];
        virtualisation.diskSize = 3000;
        virtualisation.memorySize = 2000;
      };


  };

  testScript = { nodes, ... }: let
    masterSensuCheck = testlib.sensuCheckCmd nodes.master;
  in ''
    import time
    images = [${lib.concatStringsSep "," (map (val: "\"${val}\"") images)}]

    with subtest("k3s server should work"):
      k3sserver.wait_for_unit("k3s.service")
      k3sserver.wait_until_succeeds('k3s kubectl cluster-info | grep -q https://127.0.0.1:6443')

    k3snodeA.start()

    with subtest("adding a first node should work"):
      k3snodeA.wait_for_unit("k3s.service")

      # Give k3s more time to settle without getting into IO stress when loading images.
      time.sleep(10)

      for image in images:
        k3snodeA.wait_until_succeeds(f"k3s ctr images import {image}")
      k3sserver.wait_until_succeeds("k3s kubectl get nodes | grep k3snodea | grep -vq NotReady")

    with subtest("dashboard sensu check should be green"):
      k3sserver.wait_for_unit("kube-dashboard")
      k3sserver.wait_until_succeeds("${lib.strings.escape ["\""] (masterSensuCheck "kube-dashboard")}")

    frontend.start()

    with subtest("frontend vm should reach the dashboard"):
      frontend.wait_until_succeeds('curl -k https://k3sserver.fcio.net')

    with subtest("creating a deployment should work"):
      k3sserver.wait_until_succeeds("zcat ${redis.image} | k3s ctr images import -")
      k3snodeA.wait_until_succeeds("zcat ${redis.image} | k3s ctr images import -")
      k3sserver.succeed("k3s kubectl apply -f ${redis.deployment}")
      k3sserver.succeed("k3s kubectl apply -f ${redis.service}")

    with subtest("script should generate kubeconfig for test user"):
      k3sserver.succeed("kubernetes-make-kubeconfig test > /home/test/kubeconfig")

    with subtest("test user should be able to use kubectl with generated kubeconfig"):
      k3sserver.succeed("KUBECONFIG=/home/test/kubeconfig k3s kubectl cluster-info")

    with subtest("master should be able to use cluster DNS"):
      k3sserver.wait_until_succeeds('k3s kubectl -n kube-system get pods | grep coredns | grep -v ContainerCreating | grep Running')
      k3sserver.wait_until_succeeds('dig redis.default.svc.cluster.local | grep -q 10.43')

    k3snodeB.start()
    time.sleep(5)

    with subtest("adding a second node should work"):
      for image in images:
        k3snodeB.wait_until_succeeds(f"k3s ctr images import {image}")
      k3sserver.wait_until_succeeds("k3s kubectl get nodes | grep k3snodeb | grep -vq NotReady")

    with subtest("scaling the deployment should start 4 pods"):
      k3snodeB.wait_until_succeeds("zcat ${redis.image} | k3s ctr images import -")
      k3sserver.succeed("k3s kubectl scale deployment redis --replicas=4")
      k3sserver.wait_until_succeeds("k3s kubectl get deployment redis | grep -q 4/4")

    with subtest("scaled deployment should be on two nodes"):
      k3sserver.wait_until_succeeds("k3s kubectl get pods -o wide | grep redis | grep Running | grep -q k3snodea")
      k3sserver.wait_until_succeeds("k3s kubectl get pods -o wide | grep redis | grep Running | grep -q k3snodeb")

    # with subtest("frontend should be able to ping redis pods"):
    #   print(frontend.execute("iptables -L -v --line-numbers")[1])
    #   print(k3sserver.execute("k3s kubectl -n kube-system get svc -l k8s-app=kube-dns")[1])
    #   print(k3sserver.succeed("dig @10.43.0.10 +short \*.redis.default.svc.cluster.local | xargs ${pkgs.fc.multiping}/bin/multiping"))
    #   print(k3snodeB.succeed("dig @10.43.0.10 +short \*.redis.default.svc.cluster.local | xargs ${pkgs.fc.multiping}/bin/multiping"))
    #   # print(frontend.succeed("dig @10.43.0.10 +short \*.redis.default.svc.cluster.local | xargs ${pkgs.fc.multiping}/bin/multiping"))

    with subtest("sensu should be able to access the API server endpoint"):
      k3sserver.wait_until_succeeds("stat /var/lib/k3s/tokens/sensuclient")
      # The fc-k3s-token-sensuclient unit often fails to start, try again.
      k3sserver.systemctl("reset-failed")
      k3sserver.systemctl("start fc-k3s-token-sensuclient.service")
      k3sserver.wait_for_unit("fc-k3s-token-sensuclient.service")
      k3sserver.wait_until_succeeds("${masterSensuCheck "kube-apiserver"}")
      k3sserver.wait_until_succeeds("${masterSensuCheck "kube-nodes-ready"}")

    with subtest("telegraf should be running on server"):
      # telegraf will fail to start unless the token file exists
      k3sserver.wait_for_unit("telegraf.service")
      k3sserver.wait_until_succeeds("curl -s -o /dev/null http://${masterSrv}:9126")

    with subtest("dashboard sensu check should be red after shutting down dashboard"):
      k3sserver.systemctl("stop kube-dashboard")
      k3sserver.fail("${lib.strings.escape ["\""] (masterSensuCheck "kube-dashboard")}")
  '';
})
