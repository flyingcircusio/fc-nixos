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
      {
        address = "k3sserver.fcio.net";
        ips = [
          masterSrv4
          masterSrv6
        ];
        service = "loki-collector";
      }
    ];

    # synthetic default routes are required so that connections to the
    # k3s-managed virtual service ips get routed, otherwise the
    # firewall rules won't trigger.
    extraEncParameters = {
      interfaces.srv.gateways = {
        "${testlib.fcIP.srv4 0}/24" = testlib.fcIP.srv4 254;
        "${testlib.fcIPMap.srv6.prefix}/64" = testlib.fcIP.srv6 254;
      };
    };

    redis = import ./redis.nix { inherit pkgs; };

  in
  {

    name = "k3s";
    nodes = {

      k3sserver =
        { lib, ... }:
        {
          imports = [
            (testlib.fcConfig {
              id = 2;
              inherit extraEncParameters;
            })
          ];

          config = {
            flyingcircus.encServices = encServices;
            flyingcircus.roles.k3s-server.enable = true;
            flyingcircus.roles.loki = {
              enable = true;
              storageSchedule.default = lib.mkForce [
                {
                  startDate = "2024-09-10";
                  backend = "filesystem";
                }
              ];
            };
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;
            networking.domain = "fcio.net";
            networking.hostName = lib.mkForce "k3sserver";

            networking.firewall.allowedTCPPorts = [
              8888
              6443
            ];
            networking.firewall.allowedUDPPorts = [ 53 ];

            environment.variables.LOKI_ADDR = "http://127.0.0.1:3100";
            environment.systemPackages = [ pkgs.grafana-loki ];

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

      k3snodeA =
        { config, ... }:
        {
          imports = [
            (testlib.fcConfig {
              id = 3;
              inherit extraEncParameters;
            })
          ];

          config = {
            flyingcircus.encServices = encServices;
            flyingcircus.roles.k3s-agent.enable = true;
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;

            networking.domain = "fcio.net";
            networking.hostName = lib.mkForce "k3snodeA";
            networking.nameservers = [ "127.0.0.1" ];
            virtualisation.memorySize = 2000;
            virtualisation.diskSize = 3000;

            # we can't use services.k3s.images here because we run k3s
            # with a different data directory than the default.
            systemd.tmpfiles.rules =
              let
                images = config.services.k3s.package.airgap-images;
              in
              [
                "L+ /var/lib/k3s/agent/images/airgap-images.tar.zst - - - - ${images}"
              ];
          };
        };

      k3snodeB =
        { config, ... }:
        {
          imports = [
            (testlib.fcConfig {
              id = 4;
              inherit extraEncParameters;
            })
          ];

          config = {
            flyingcircus.encServices = encServices;
            flyingcircus.roles.k3s-agent.enable = true;
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;

            networking.domain = "fcio.net";
            networking.hostName = lib.mkForce "k3snodeB";
            virtualisation.memorySize = 2000;
            virtualisation.diskSize = 3000;

            systemd.tmpfiles.rules =
              let
                images = config.services.k3s.package.airgap-images;
              in
              [
                "L+ /var/lib/k3s/agent/images/airgap-images.tar.zst - - - - ${images}"
              ];
          };
        };

      frontend =
        { pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig {
              id = 1;
              inherit extraEncParameters;
            })
          ];

          config = {
            flyingcircus.roles.webgateway.enable = true;
            networking.domain = "fcio.net";
            flyingcircus.encServices = encServices;
            virtualisation.diskSize = 3000;
            virtualisation.memorySize = 2000;
            environment.systemPackages = [ pkgs.redis ];
            flyingcircus.kubernetes.network.enableIPv6 = enableIPv6;
            flyingcircus.kubernetes.frontend.redis = {
              binds = [ "127.0.0.1:6379" ];
              servicePort = 6379;
              mode = "tcp";
            };
          };
        };

    };

    testScript =
      { nodes, ... }:
      let
        k3sserverSensuCheck = testlib.sensuCheckCmd nodes.k3sserver;
        testscript = pkgs.writeShellScript "test-podlog-in-loki.sh" ''
          test $(logcli -q query '{container="redis"} |= `Redis is starting`' | wc -l) -gt 0
        '';
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
            lib.strings.escape [ "\"" ] (k3sserverSensuCheck "kube-dashboard")
          }")

        frontend.start()

        with subtest("frontend vm should reach the dashboard"):
          frontend.wait_until_succeeds('curl -k http://k3sserver.fcio.net')

        with subtest("creating a deployment should work"):
          k3snodeA.succeed("k3s ctr images import ${redis.image}")
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
          k3sserver.wait_until_succeeds("k3s kubectl get nodes | grep k3snodeb | grep -vq NotReady")

        with subtest("scaling the deployment should start 4 pods"):
          k3snodeB.succeed("k3s ctr images import ${redis.image}")
          k3sserver.succeed("k3s kubectl scale deployment redis --replicas=4")
          k3sserver.wait_until_succeeds("k3s kubectl get deployment redis | grep -q 4/4")

        with subtest("scaled deployment should be on two nodes"):
          k3sserver.wait_until_succeeds("k3s kubectl get pods -o wide | grep redis | grep Running | grep -q k3snodea")
          k3sserver.wait_until_succeeds("k3s kubectl get pods -o wide | grep redis | grep Running | grep -q k3snodeb")

        with subtest("frontend should be able to ping redis pods"):
          frontend.wait_until_succeeds("redis-cli ping | grep PONG")

        with subtest("redis logs are shipped to loki"):
          k3sserver.succeed('${testscript}')

        with subtest("dashboard sensu check should be red after shutting down dashboard"):
          k3sserver.systemctl("stop kube-dashboard")
          k3sserver.fail("${lib.strings.escape [ "\"" ] (k3sserverSensuCheck "kube-dashboard")}")
      '';
  }
)
