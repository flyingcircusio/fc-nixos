import ../make-test-python.nix ({ lib, pkgs, testlib, ... }:
with builtins;

let

  pauseImage = pkgs.dockerTools.pullImage {
    imageName = "rancher/pause";
    imageDigest = "sha256:d22591b61e9c2b52aecbf07106d5db313c4f178e404d660b32517b18fcbf0144";
    sha256 = "0vrc3flx239qmvigzfcv1swn447722bsc5ah5nn055jqa4m3i82p";
    finalImageName = "rancher/pause";
    finalImageTag = "3.1";
  };

  klipperHelmImage = pkgs.dockerTools.pullImage {
    imageName = "rancher/klipper-helm";
    imageDigest = "sha256:b319bce4802b8e42d46e251c7f9911011a16b4395a84fa58f1cf4c788df17139";
    sha256 = "1px6y7qmxkv702pjnhfkpv0qz7l8257nvcfv7h5mwgxnmh6v6617";
    finalImageName = "rancher/klipper-helm";
    finalImageTag = "v0.4.3";
  };

  metricsServerImage = pkgs.dockerTools.pullImage {
    imageName = "rancher/metrics-server";
    imageDigest = "sha256:b85628b103169d7db52a32a48b46d8942accb7bde3709c0a4888a23d035f9f1e";
    sha256 = "176iglsg0pgd23g3a9hkn43jq781hj7z7625ifh46xki9iv2gfph";
    finalImageName = "rancher/metrics-server";
    finalImageTag = "v0.3.6";
  };

  corednsImage = pkgs.dockerTools.pullImage {
    imageName = "rancher/coredns-coredns";
    imageDigest = "sha256:9d4f5d7968c432fbd4123f397a2d6ab666fd63d13d510d9728d717c3e002dc72";
    sha256 = "1jlr7rnqq48izi8n69h0alzpfz8fb22dpr7ylaphcsj5grnpsgkq";
    finalImageName = "rancher/coredns-coredns";
    finalImageTag = "1.8.3";
  };

  libraryTraefikImage = pkgs.dockerTools.pullImage {
    imageName = "rancher/library-traefik";
    imageDigest = "sha256:343de3610780fc88b04eeb2145cbf8189e8f6278c2061de4a1e10de31711c252";
    sha256 = "06dvzmap51z9dggm9z4xax4vcb14cqz5301c629grkiylz60vdrp";
    finalImageName = "rancher/library-traefik";
    finalImageTag = "2.4.8";
  };

  klipperLBImage = pkgs.dockerTools.pullImage {
    imageName = "rancher/klipper-lb";
    imageDigest = "sha256:2fb97818f5d64096d635bc72501a6cb2c8b88d5d16bc031cf71b5b6460925e4a";
    sha256 = "0f8si6wwqs4d73lxgn91bp6zq5sp3pz2yki92dqviy3gc9n8w05k";
    finalImageName = "rancher/klipper-lb";
    finalImageTag = "v0.1.2";
  };

  localPathProvisionerImage = pkgs.dockerTools.pullImage {
    imageName = "rancher/local-path-provisioner";
    imageDigest = "sha256:9666b1635fec95d4e2251661e135c90678b8f45fd0f8324c55db99c80e2a958c";
    sha256 = "03nhj2j86v818s9pj5jaly33v3y2yza4qnv9n0763qi67wvmlziz";
    finalImageName = "rancher/local-path-provisioner";
    finalImageTag = "v0.0.19";
  };

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

        virtualisation.memorySize = 4000;
        virtualisation.diskSize = lib.mkForce 2000;
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
        virtualisation.diskSize = 2000;
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
        virtualisation.diskSize = 2000;
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
        virtualisation.diskSize = 2000;
        virtualisation.memorySize = 2000;
      };


  };

  testScript = { nodes, ... }: let
    masterSensuCheck = testlib.sensuCheckCmd nodes.master;
  in ''
    with subtest("k3s server should work"):
      k3sserver.wait_for_unit("k3s.service")
      k3sserver.wait_until_succeeds('k3s kubectl cluster-info | grep -q https://127.0.0.1:6443')

    with subtest("adding a first node should work"):
      k3snodeA.wait_for_unit("k3s.service")
      k3snodeA.succeed("k3s ctr images import ${pauseImage}")
      k3snodeA.succeed("k3s ctr images import ${klipperHelmImage}")
      k3snodeA.succeed("k3s ctr images import ${metricsServerImage}")
      k3snodeA.succeed("k3s ctr images import ${corednsImage}")
      k3snodeA.succeed("k3s ctr images import ${libraryTraefikImage}")
      k3snodeA.succeed("k3s ctr images import ${klipperLBImage}")
      k3snodeA.succeed("k3s ctr images import ${localPathProvisionerImage}")
      k3sserver.wait_until_succeeds("k3s kubectl get nodes | grep k3snodea | grep -vq NotReady")

    with subtest("dashboard sensu check should be green"):
      k3sserver.wait_for_unit("kube-dashboard")
      k3sserver.wait_until_succeeds("${lib.strings.escape ["\""] (masterSensuCheck "kube-dashboard")}")

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

    with subtest("adding a second node should work"):
      k3snodeB.wait_for_unit("k3s.service")
      k3snodeB.succeed("k3s ctr images import ${pauseImage}")
      k3snodeB.succeed("k3s ctr images import ${klipperHelmImage}")
      k3snodeB.succeed("k3s ctr images import ${metricsServerImage}")
      k3snodeB.succeed("k3s ctr images import ${corednsImage}")
      k3snodeB.succeed("k3s ctr images import ${libraryTraefikImage}")
      k3snodeB.succeed("k3s ctr images import ${klipperLBImage}")
      k3snodeB.succeed("k3s ctr images import ${localPathProvisionerImage}")
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

    with subtest("dashboard sensu check should be red after shutting down dashboard"):
      k3sserver.systemctl("stop kube-dashboard")
      k3sserver.fail("${lib.strings.escape ["\""] (masterSensuCheck "kube-dashboard")}")
  '';
})
