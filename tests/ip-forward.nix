import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    assertZeroSysctl = pkgs.writeScriptBin "assert_zero_sysctl" ''
      set -eu
      sysctl="$1"

      value="$(${pkgs.procps}/bin/sysctl -n -b "$sysctl")"

      [ "$value" == "0" ]
    '';
  in
  {
    name = "ip-forward";
    nodes = {
      middle =
        { ... }:
        {
          imports = [ (testlib.fcConfig { id = 1; }) ];
          environment.systemPackages = [ assertZeroSysctl ];
        };
      left =
        { ... }:
        {
          imports = [
            (testlib.fcConfig {
              id = 2;
              net.fe = false;
            })
          ];
          environment.systemPackages = [ assertZeroSysctl ];
        };
      right =
        { ... }:
        {
          imports = [
            (testlib.fcConfig {
              id = 3;
              net.srv = false;
            })
          ];
          environment.systemPackages = [ assertZeroSysctl ];
          services.telegraf.enable = false;
        };
    };
    testScript = ''
      hosts = [left, middle, right]

      start_all()
      for host in hosts:
          host.wait_for_unit("multi-user.target")

      with subtest("check host routes"):
          for host in hosts:
              out = host.succeed("ip route")
              print(out)
              out = host.succeed("ip -6 route")
              print(out)

      # first check whether in practice forwarding is evidentially disabled
      with subtest("check that intermediate host does not forward ipv4 packets"):
          left.succeed("ip route add 192.168.2.3/32 via 192.168.3.1")
          right.succeed("ip route add 192.168.3.2/32 via 192.168.2.1")

          left.fail("ping -A -c5 192.168.2.3")
          right.fail("ping -A -c5 192.168.3.2")

      with subtest("check that intermediate host does not forward ipv6 packets"):
          left.succeed("ip route add 2001:db8:2::3/128 via 2001:db8:3::1")
          right.succeed("ip route add 2001:db8:3::2/128 via 2001:db8:2::1")

          left.fail("ping -A -c5 2001:db8:2::3")
          right.fail("ping -A -c5 2001:db8:3::2")

      # then check that the sysctls are set correctly in the kernel
      with subtest("check that forwarding sysctls are disabled"):
          for host in hosts:
              host.succeed("assert_zero_sysctl net.ipv4.ip_forward")
              host.succeed("assert_zero_sysctl net.ipv4.conf.all.forwarding")
              host.succeed("assert_zero_sysctl net.ipv4.conf.default.forwarding")
              host.succeed("assert_zero_sysctl net.ipv6.conf.all.forwarding")
              host.succeed("assert_zero_sysctl net.ipv6.conf.default.forwarding")
    '';
  }
)
