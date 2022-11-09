import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:

let
  redisImage = pkgs.dockerTools.buildImage {
    name = "redis";
    tag = "latest";
    contents = [ pkgs.redis ];
    config.Cmd = [ "/bin/redis-server" "--protected-mode no" ];
  };
in
{
  name = "docker";
  nodes = {
    machine =
      { pkgs, lib, config, ... }:
      {
        imports = [ (testlib.fcConfig {}) ];
        flyingcircus.roles.docker.enable = true;
      };
    };

  testScript = ''
    machine.wait_for_unit('docker.socket')

    with subtest("docker version should work"):
      output = machine.succeed("docker version")

    with subtest("docker should be able to import an image"):
      machine.succeed("docker load < ${redisImage}")

    with subtest("docker should be able to start a container"):
      machine.succeed("docker run -d -p 127.0.0.1:6379:6379 redis")

    with subtest("redis in container should be reachable"):
      machine.succeed("${pkgs.redis}/bin/redis-cli LOLWUT")

    with subtest("sysctl forwarding should be enabled"):
      # Taken from upstream test
      machine.succeed("grep 1 /proc/sys/net/ipv4/conf/all/forwarding")
      machine.succeed("grep 1 /proc/sys/net/ipv4/conf/default/forwarding")
  '';
})
