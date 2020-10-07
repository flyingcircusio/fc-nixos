import ../make-test-python.nix ({ lib, pkgs, testlib, ... }:
with builtins;

let
  net4Srv = "10.0.1";
  frontendSrv = net4Srv + ".1";
  masterSrv = net4Srv + ".2";
  nodeSrv = net4Srv + ".3";

  net4Fe = "10.0.2";
  masterFe = net4Fe + ".1";

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
    ${masterFe} kubernetes.test.fcio.net
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
        networking.firewall.allowedUDPPorts = [ 53 ];
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
        networking.extraHosts = hosts;
        flyingcircus.encServices = encServices;
        virtualisation.vlans = [ 1 ];
      };


  };

  testScript = { nodes, ... }: let
    masterSensuCheck = testlib.sensuCheckCmd nodes.master;
  in ''

    with subtest("kube master should work"):
      kubmaster.wait_for_unit("kubernetes.target")
      kubmaster.wait_until_succeeds('kubectl cluster-info | grep -q https://kubmaster.fcio.net:6443')
      kubmaster.systemctl("restart fc-kubernetes-setup")

    with subtest("dashboard sensu check should be green"):
      kubmaster.wait_for_unit("kube-dashboard")
      kubmaster.wait_until_succeeds("${masterSensuCheck "kube-dashboard"}")

    with subtest("coredns sensu check should be green"):
      kubmaster.wait_for_unit("coredns")
      kubmaster.wait_until_succeeds("${masterSensuCheck "cluster-dns"}")

    with subtest("frontend vm should reach the dashboard"):
      frontend.wait_until_succeeds('curl -k https://kubmaster.fcio.net')

    with subtest("creating a deployment should work"):
      kubmaster.wait_for_unit("docker")
      kubmaster.wait_for_unit("kubelet")
      kubmaster.wait_until_succeeds("docker load < ${redis.image}")
      kubmaster.succeed("kubectl apply -f ${redis.deployment}")
      kubmaster.succeed("kubectl apply -f ${redis.service}")

    with subtest("script should generate kubeconfig for test user"):
      kubmaster.succeed("kubernetes-make-kubeconfig test > /home/test/kubeconfig")

    with subtest("test user should be able to use kubectl with generated kubeconfig"):
      kubmaster.succeed("KUBECONFIG=/home/test/kubeconfig kubectl cluster-info")

    with subtest("secret key for test user should have correct permissions"):
      kubmaster.succeed("stat /var/lib/kubernetes/secrets/test-key.pem -c %a:%U:%G | grep '600:test:nogroup'")

    with subtest("master should be able to use cluster DNS"):
      kubmaster.wait_until_succeeds('dig redis.default.svc.cluster.local | grep -q 10.0.0')

    with subtest("adding a second node should work"):
      kubnode.wait_for_unit("kubernetes.target")
      kubmaster.wait_until_succeeds("kubectl get nodes | grep kubnode | grep -vq NotReady")

    with subtest("scaling the deployment should start 4 pods"):
      kubnode.wait_until_succeeds("docker load < ${redis.image}")
      kubmaster.succeed("kubectl scale deployment redis --replicas=4")
      kubmaster.wait_until_succeeds("kubectl get deployment redis | grep -q 4/4")

    with subtest("node should be able to use cluster DNS"):
      kubnode.wait_until_succeeds('dig redis.default.svc.cluster.local | grep -q 10.0.0')

    with subtest("frontend should be able to use cluster DNS"):
      frontend.wait_until_succeeds('dig redis.default.svc.cluster.local | grep -q 10.0.0')

    with subtest("coredns sensu check should be red after shutting down coredns"):
      kubmaster.systemctl("stop coredns")
      kubmaster.fail("${masterSensuCheck "cluster-dns"}")

    with subtest("dashboard sensu check should be red after shutting down dashboard"):
      kubmaster.systemctl("stop kube-dashboard")
      kubmaster.fail("${masterSensuCheck "kube-dashboard"}")
  '';
})
