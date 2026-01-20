import ../make-test-python.nix (
  {
    lib,
    pkgs,
    testlib,
    enableIPv6 ? false,
    ...
  }:
  let

    masterSrv4 = testlib.fcIP.srv4 2;
    masterSrv6 = testlib.fcIP.srv6 2;
    nodeSrvA4 = testlib.fcIP.srv4 3;
    nodeSrvA6 = testlib.fcIP.srv6 3;
    nodeSrvB4 = testlib.fcIP.srv4 4;
    nodeSrvB6 = testlib.fcIP.srv6 4;
    frontendSrv4 = testlib.fcIP.fe4 1;
    frontendSrv6 = testlib.fcIP.fe6 1;

    encServices = [
      {
        address = "k3sserver.fcio.net";
        ips = [
          masterSrv4
          masterSrv6
        ];
        service = "k3s-server-server";
        password = "xvlc";
      }
      {
        address = "k3snodeA.fcio.net";
        ips = [
          nodeSrvA4
          nodeSrvA6
        ];
        service = "k3s-node";
      }
      {
        address = "k3snodeB.fcio.net";
        ips = [
          nodeSrvB4
          nodeSrvB6
        ];
        service = "k3s-node";
      }
      {
        address = "frontend.fcio.net";
        ips = [
          frontendSrv4
          frontendSrv6
        ];
        service = "k3s-frontend";
      }
    ];

    redis = import ./redis.nix { inherit pkgs; };

  in
  {

    name = "k3s";

    nodes = {

      master =
        { lib, ... }:
        {
          imports = [ (testlib.fcConfig { id = 2; }) ];

          config = {
            flyingcircus.encServices = encServices;
            flyingcircus.roles.k3s-server.enable = true;
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;
            networking.domain = "fcio.net";
            networking.hostName = lib.mkForce "k3sserver";

            networking.firewall.allowedTCPPorts = [
              8888
              6443
            ];
            networking.firewall.allowedUDPPorts = [ 53 ];

            services.nginx.virtualHosts."kubernetes.test.fcio.net" = {
              enableACME = false;
              forceSSL = false;
            };

            users.groups = {
              sudo-srv = { };
            };
            users.users = {
              sensuclient = {
                isSystemUser = true;
              };
            };

            flyingcircus.users.userData = [
              {
                id = 1001;
                uid = "test";
                name = "test";
                permissions = {
                  test = [ "sudo-srv" ];
                };
                password = "";
                home_directory = "/home/test";
                login_shell = "/bin/bash";
                class = "human";
                ssh_pubkey = [ ];
              }
            ];

            virtualisation.memorySize = 2000;
            virtualisation.diskSize = lib.mkForce 3000;
            virtualisation.qemu.options = [ "-smp 2" ];
          };
        };

      nodeA =
        { ... }:
        {
          imports = [ (testlib.fcConfig { id = 3; }) ];

          config = {
            flyingcircus.encServices = encServices;
            flyingcircus.roles.k3s-agent.enable = true;
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;

            networking.domain = "fcio.net";
            networking.hostName = lib.mkForce "k3snodeA";
            networking.nameservers = [ "127.0.0.1" ];
            virtualisation.memorySize = 2000;
            virtualisation.diskSize = 3000;
          };
        };

      nodeB =
        { ... }:
        {
          imports = [ (testlib.fcConfig { id = 4; }) ];

          config = {
            flyingcircus.encServices = encServices;
            flyingcircus.roles.k3s-agent.enable = true;
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;

            networking.domain = "fcio.net";
            networking.hostName = lib.mkForce "k3snodeB";
            virtualisation.memorySize = 2000;
            virtualisation.diskSize = 3000;
          };
        };

      frontend =
        { ... }:
        {
          imports = [ (testlib.fcConfig { id = 1; }) ];

          config = {
            flyingcircus.roles.webgateway.enable = true;
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;
            networking.domain = "fcio.net";
            flyingcircus.encServices = encServices;
            virtualisation.diskSize = 3000;
            virtualisation.memorySize = 2000;
          };
        };

    };

    testScript =
      { nodes, ... }:
      let
        masterSensuCheck = testlib.sensuCheckCmd nodes.master;
      in
      ''
        import time

        with subtest("k3s server should work"):
          k3sserver.wait_for_unit("k3s.service")
          k3sserver.wait_until_succeeds('k3s kubectl get --raw=/healthz | grep -q ok')
          k3sserver.succeed('k3s kubectl get node k3sserver -o jsonpath=\'{.status.conditions[?(@.type=="Ready")].status}\' | grep -q True')

        k3snodeA.start()

        with subtest("adding a first node should work"):
          k3snodeA.wait_for_unit("k3s.service")

          # Give k3s more time to settle without getting into IO stress when loading images.
          time.sleep(10)

          # XXX: for some reason *implicit* image import via
          # `services.k3s.images = [ config.services.k3s.package.airgap-images ];` does not work.
          # Doing a manual import instead.
          k3snodeA.wait_until_succeeds("echo 'try import' >2; k3s ctr images import ${nodes.nodeA.services.k3s.package.airgap-images} >2")
          k3sserver.wait_until_succeeds("k3s kubectl get nodes | grep k3snodea | grep -vq NotReady")

        with subtest("all kube-system images pulled successfully"):
          print("waiting for containers to be created…")
          print(k3sserver.execute("k3s kubectl -n kube-system get pods")[1])
          k3sserver.wait_until_succeeds("k3s kubectl -n kube-system get pods | grep -zvq ContainerCreating")
          if k3sserver.execute("k3s kubectl -n kube-system get pods | grep -zvq ErrImagePull")[0]:
            print(k3sserver.execute("k3s kubectl -n kube-system get pods")[1])
            raise AssertionError("Error pulling some images. Make sure that the "
              "airgapped-images are up to date and matching your package.")

        with subtest("dashboard sensu check should be green"):
          k3sserver.wait_for_unit("kube-dashboard")
          k3sserver.wait_until_succeeds("${
            lib.strings.escape [ "\"" ] (masterSensuCheck "kube-dashboard")
          }")

        frontend.start()

        with subtest("frontend vm should reach the dashboard"):
          frontend.wait_until_succeeds('curl -k http://k3sserver.fcio.net')

        with subtest("creating a deployment should work"):
          k3sserver.wait_until_succeeds("zcat ${redis.image} | k3s ctr images import -")
          k3snodeA.wait_until_succeeds("zcat ${redis.image} | k3s ctr images import -")
          k3sserver.succeed("k3s kubectl apply -f ${redis.deployment}")
          k3sserver.succeed("k3s kubectl apply -f ${redis.service}")

        with subtest("script should generate kubeconfig for test user"):
          k3sserver.succeed("kubernetes-make-kubeconfig test > /home/test/kubeconfig")

        with subtest("test user should be able to use kubectl with generated kubeconfig"):
          k3sserver.succeed("KUBECONFIG=/home/test/kubeconfig k3s kubectl cluster-info")

        with subtest("master should be able to reach cluster DNS"):
          time.sleep(1)
          k3sserver.wait_until_succeeds('k3s kubectl -n kube-system get pods | grep coredns | grep -v ContainerCreating | grep Running')

        k3snodeB.start()
        time.sleep(5)

        with subtest("adding a second node should work"):

          k3snodeB.wait_until_succeeds("k3s ctr images import ${nodes.nodeA.services.k3s.package.airgap-images} >2")
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
          k3sserver.fail("${lib.strings.escape [ "\"" ] (masterSensuCheck "kube-dashboard")}")
      '';
  }
)
