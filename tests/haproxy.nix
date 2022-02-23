with builtins;

import ./make-test-python.nix ({ pkgs, testlib, ... }:

let
  release = import ../release {};
  channel = release.release.src;
  configSplit1of2 = ''
         global
           #comment1 to grep for
           daemon
           chroot /var/empty
           log 127.0.0.1 local2

         defaults
           mode http
           log global
           option httplog
           timeout connect 5s
           timeout client 5s
           timeout server 5s

     '';
  configSplit2of2 = ''
         frontend http-in
           #comment2 to grep for
           bind *:8888
           default_backend server

         backend server
           server python 127.0.0.1:7000

     '';
  configComplete = configSplit1of2 + configSplit2of2;

in
{
  name = "haproxy";
  nodes = {
    machine =
      { lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:34:56";
            bridged = false;
            networks = {
              "192.168.101.0/24" = [ "192.168.101.1" ];
              "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
            };
            gateways = {};
          };
        };

        environment.etc."nixpkgs-paths-debug".text = toJSON {
          pkgs = "${pkgs.path}";
          releaseChannelSrc = "${channel}";
          nixpkgs = "${<nixpkgs>}";
        };

        environment.etc."nixos/local.nix".text = ''
          { ... }:
          {
            # Only a dummy to make nixos-rebuild inside the test VM work.
          }
        '';

        environment.etc."local/nixos/synced_config.nix".text = ''
          { config, pkgs, lib, ... }:
          {
            # !!! If you use this test as a template for another test that wants to
            # use nixos-rebuild inside the VM:
            # You may have to change config here (used for rebuilds inside the VM)
            # when you change settings on the "outside" (used to build the VM on the test host).
            # Configs need to be in sync or nixos-rebuild will try to build
            # more stuff which may fail because networking isn't available inside
            # the test VM.

            flyingcircus.services.haproxy.enable = true;
            services.telegraf.enable = false;

          }
        '';

        system.extraDependencies = with pkgs; [
          # Taken from nixpkgs tests/ec2.nix
          busybox
          cloud-utils
          desktop-file-utils
          libxslt.bin
          mkinitcpio-nfs-utils
          stdenv
          stdenvNoCC
          texinfo
          unionfs-fuse
          xorg.lndir
          # Our custom stuff that's needed to rebuild the VM.
          php
          channel
        ];

        # nix-env -qa needs a lot of RAM. Crashed with 2000.
        virtualisation.memorySize = 3000;

        flyingcircus.services.haproxy.enable = true;

        services.haproxy.config = lib.mkForce ''
          global
            daemon
            chroot /var/empty
            log 127.0.0.1 local2

          defaults
            mode http
            log global
            option httplog
            timeout connect 5s
            timeout client 5s
            timeout server 5s

          frontend http-in
            bind *:8888
            default_backend server

          backend server
            server python 127.0.0.1:7000
        '';
      };
  };
  testScript = { nodes, ... }: ''
    machine.wait_for_unit("haproxy.service")
    machine.wait_for_unit("syslog.service")

    machine.execute("""
      echo 'Hello World!' > hello.txt
      ${pkgs.python3.interpreter} -m http.server 7000 >&2 &
    """)

    with subtest("request through haproxy should succeed"):
      machine.succeed("curl -s http://localhost:8888/hello.txt | grep -q 'Hello World!'")

    with subtest("log file entry should be present for request"):
      machine.sleep(1)
      machine.succeed('grep "haproxy.* http-in server/python .* /hello.txt" /var/log/haproxy.log')

    with subtest("service user should be able to write to local config dir"):
      machine.succeed('sudo -u haproxy touch /etc/local/haproxy/haproxy.cfg')

    with subtest("reload should work"):
      machine.succeed("systemctl reload haproxy")
      machine.wait_until_succeeds('journalctl -g "Reloaded HAProxy" --no-pager')

    with subtest("reload should trigger a restart if /run/haproxy is missing"):
      machine.execute("rm -rf /run/haproxy")
      machine.succeed("systemctl reload haproxy")
      machine.wait_until_succeeds("stat /run/haproxy/haproxy.sock 2> /dev/null")
      machine.wait_until_succeeds('journalctl -g "Socket not present which is needed for reloading, restarting instead" --no-pager')

    with subtest("sensu haproxy config check should be green"):
      machine.succeed("${testlib.sensuCheckCmd nodes.machine "haproxy_config"}")

    with subtest("haproxy check script should be green"):
      machine.succeed("${pkgs.fc.check-haproxy}/bin/check_haproxy /var/log/haproxy.log")

    with subtest("haproxy.cfg should be read after rebuild"):
      machine.execute("ln -s ${channel} /nix/var/nix/profiles/per-user/root/channels")
      machine.execute("""echo $'${configComplete}' > /etc/local/haproxy/haproxy.cfg""")
      machine.succeed("nixos-rebuild build --option substitute false")
      machine.succeed("grep -c '#comment1 to grep for' result/etc/haproxy.cfg")

    with subtest("haproxy1.cfg and haproxy2.cfg should be read after rebuild"):
      machine.execute("rm /etc/local/haproxy/haproxy.cfg")
      machine.execute("""echo $'${configSplit1of2}' > /etc/local/haproxy/haproxy1.cfg""")
      machine.execute("""echo $'${configSplit2of2}' > /etc/local/haproxy/haproxy2.cfg""")
      machine.succeed("nixos-rebuild build --option substitute false")
      machine.succeed("grep -c '#comment1 to grep for' result/etc/haproxy.cfg")
      machine.succeed("grep -c '#comment2 to grep for' result/etc/haproxy.cfg")

  '';

})
