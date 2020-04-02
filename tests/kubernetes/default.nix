import ../make-test.nix ({ lib, pkgs, testlib, ... }:
with builtins;

let
  net4Srv = "10.0.1";
  frontendSrv = net4Srv + ".1";
  masterSrv = net4Srv + ".2";
  nodeSrv = net4Srv + ".3";

  net4Fe = "10.0.2";
  masterFe = net4Fe + ".1";

  dashboardFQDN = "kubernetes-dashboard.kube-system.svc.cluster.local";

  encServices = [
    {
      address = "kubmaster.fcio.net";
      ips = [ masterSrv ];
      service = "kubernetes-master-master";
      password = "xvlc";
    }
    {
      address = "kubmaster.fcio.net";
      ips = [ masterSrv ];
      service = "kubernetes-node-node";
    }
    {
      address = "kubnode.fcio.net";
      ips = [ nodeSrv ];
      service = "kubernetes-node-node";
    }
  ];

  hosts = ''
    ${masterSrv} kubmaster.fcio.net
    ${nodeSrv} kubnode.fcio.net
    ${masterFe} kubmaster.fe.test.fcio.net
  '';

  redis = import ./redis.nix { inherit pkgs; };

in {

  name = "kubernetes";
  nodes = {

    master =
      { ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];

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
        flyingcircus.roles.kubernetes-master.enable = true;
        flyingcircus.roles.kubernetes-node.enable = true;
        networking.domain = "fcio.net";
        networking.hostName = lib.mkForce "kubmaster";
        networking.extraHosts = hosts;

        networking.firewall.allowedTCPPorts = [ 8888 6443 ];
        users.groups = {
          sudo-srv = {};
        };
        users.users = {
          sensuclient = {};
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
        virtualisation.diskSize = lib.mkForce 1000;
        services.flannel.iface = "ethsrv";
        virtualisation.vlans = [ 1 2 ];
      };

    node =
      { ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            bridged = false;
            mac = "52:54:00:12:01:03";
            networks = {
              "${net4Srv}.0/24" = [ nodeSrv ];
            };
            gateways = { "${net4Srv}.0/24" = "${net4Srv}.254"; };
          };
        };
        flyingcircus.encServices = encServices;
        flyingcircus.roles.kubernetes-node.enable = true;

        networking.domain = "fcio.net";
        networking.extraHosts = hosts;
        networking.hostName = lib.mkForce "kubnode";
        virtualisation.memorySize = 2000;
        services.flannel.iface = "ethsrv";
        virtualisation.diskSize = 1000;
        virtualisation.vlans = [ 1 ];
        virtualisation.docker.storageDriver = "devicemapper";
      };

    frontend =
      { ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];

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
        };
        flyingcircus.encServices = encServices;
        virtualisation.vlans = [ 1 ];
      };


  };

  testScript = { nodes, ... }:
  let
    dashboardIP = nodes.master.config.flyingcircus.roles.kubernetes-master.dashboardClusterIP;
  in ''
    subtest "kube master should work", sub {
      $kubmaster->waitForUnit("kubernetes.target");
      $kubmaster->succeed('kubectl cluster-info | grep -q https://kubmaster.fcio.net:6443');
    };

    subtest "frontend vm should reach the dashboard via service IP", sub {
      $frontend->waitUntilSucceeds('curl -k https://${dashboardIP}');
    };

    subtest "frontend vm should be able to use cluster DNS", sub {
      $frontend->waitUntilSucceeds('dig @10.0.0.254 ${dashboardFQDN} | grep -q ${dashboardIP}');
    };

    subtest "creating a deployment should work", sub {
      $kubmaster->succeed("docker load < ${redis.image}");
      $kubmaster->succeed("kubectl apply -f ${redis.deployment}");
      $kubmaster->succeed("kubectl apply -f ${redis.service}");
    };

    subtest "adding a second node should work", sub {
      $kubnode->waitForUnit("kubernetes.target");
      $kubmaster->waitUntilSucceeds("kubectl get nodes | grep kubnode | grep -vq NotReady");
    };

    subtest "scaling the deployment should start 4 pods", sub {
      $kubnode->succeed("docker load < ${redis.image}");
      $kubmaster->succeed("kubectl scale deployment redis --replicas=4");
      $kubmaster->waitUntilSucceeds("kubectl get deployment redis | grep -q 4/4");
    };

    subtest "script should generate kubeconfig for test user", sub {
      $kubmaster->succeed("kubernetes-make-kubeconfig test > /home/test/kubeconfig");
    };

    subtest "test user should be able to use kubectl with generated kubeconfig", sub {
      $kubmaster->succeed("KUBECONFIG=/home/test/kubeconfig kubectl cluster-info");
    };

    subtest "secret key for test user should have correct permissions", sub {
      $kubmaster->succeed("stat /var/lib/kubernetes/secrets/test-key.pem -c %a:%U:%G | grep '600:test:nogroup'");
    };
  '';
})
