import ./make-test-python.nix ({ lib, ... }:

let
  userData =
    (lib.mapAttrsToList (id: groups: {
      class = "human";
      gid = 100;
      home_directory = "/home/u${id}";
      id = builtins.fromJSON id;
      login_shell = "/bin/bash";
      name = "Human User";
      # password = hum1pass
      password = "$6$tCkMUKawIO9w90qR$e0v.8fedV8mm.kLs7M9zN6z0tYG9YLpuJxCM.KiB4P4Nf7lU1l9P7HSbTuziLzjRR/qBrcf.BJRjajrAid1sl.";
      permissions.test = groups;
      ssh_pubkey = [];
      uid = "u${id}";
    })
    {
      "1000" = [ ];
      "1001" = [ "admins" ];
      "1002" = [ "sudo-srv" ];
      "1003" = [ "wheel" ];
      "1004" = [ "wheel" "sudo-srv" ];
    }) ++ [
      {
        class = "service";
        gid = 101;
        home_directory = "/home/s-service";
        id = 1074;
        login_shell = "/bin/bash";
        name = "s-service";
        # password = hum1pass
        password = "$6$tCkMUKawIO9w90qR$e0v.8fedV8mm.kLs7M9zN6z0tYG9YLpuJxCM.KiB4P4Nf7lU1l9P7HSbTuziLzjRR/qBrcf.BJRjajrAid1sl.";
        permissions.test = [];
        ssh_pubkey = [];
        uid = "s-service";
      }
    ];

in
{
  name = "sudo";
  machine =
    { pkgs, lib, config, ... }:
    {
      imports = [
        ../nixos
      ];

      flyingcircus.users = {
        userData = userData;
        permissions = [
          {
            id = 2028;
            name = "sudo-srv";
          }
        ];
        adminsGroup = {
          gid = 2003;
          name = "admins";
        };
      };

      flyingcircus.enc.parameters.resource_group = "test";

      services.telegraf.enable = false;

    };

  testScript = ''
    machine.wait_for_unit('multi-user.target')

    with subtest("check uids"):
        out = machine.succeed("id u1000")
        assert (out == "uid=1000(u1000) gid=100(users) groups=100(users)\n"), out
        out = machine.succeed("id u1001")
        assert (out == "uid=1001(u1001) gid=100(users) groups=2003(admins),100(users)\n"), out
        out = machine.succeed("id u1002")
        assert (out == "uid=1002(u1002) gid=100(users) groups=503(sudo-srv),100(users)\n"), out
        out = machine.succeed("id u1003")
        assert (out == "uid=1003(u1003) gid=100(users) groups=1(wheel),100(users)\n"), out
        out = machine.succeed("id u1004")
        assert (out == "uid=1004(u1004) gid=100(users) groups=1(wheel),503(sudo-srv),100(users)\n"), out
        out = machine.succeed("id s-service")
        assert (out == "uid=1074(s-service) gid=900(service) groups=900(service)\n"), out

    def login(user, tty):
        machine.send_key(f"alt-f{tty}")
        machine.sleep(1)
        machine.wait_until_tty_matches(tty, "login:")
        machine.send_chars(f"{user}\n")
        machine.sleep(1)
        machine.wait_until_tty_matches(tty, "Password:")
        machine.send_chars("hum1pass\n")
        machine.sleep(1)
        machine.wait_until_tty_matches(tty, "$")

    # Each user gets its own tty.
    # Avoids strange logout problems and keeps the output for interactive inspection.
    # Inspect tty contents in the interactive test driver with:
    # print(machine.get_tty_text(1))

    login("u1000", 1)

    with subtest("unprivileged user should not be able to sudo"):
        machine.send_chars("sudo -l -u root id || echo failed1\n")
        machine.wait_until_tty_matches(1, "failed1")
        machine.send_chars("sudo -l -u s-service id || echo failed2\n")
        machine.wait_until_tty_matches(1, "failed2")

    with subtest("unprivileged user should be able to run ipXtables without password"):
        machine.send_chars("sudo -n iptables && echo 'pw not required iptables'\n")
        machine.wait_until_tty_matches(1, "pw not required iptables")

        machine.send_chars("sudo -n ip6tables && echo 'pw not required ip6tables'\n")
        machine.wait_until_tty_matches(1, "pw not required ip6tables")

    login("u1001", 2)

    with subtest("admins should be able to sudo"):
        machine.send_chars("sudo -l -u root id || echo failed3\n")
        machine.wait_until_tty_matches(2, "/run/current-system/sw/bin/id")
        machine.send_chars("sudo -l -u s-service id || echo failed4\n")
        machine.wait_until_tty_matches(2, "/run/current-system/sw/bin/id")

    with subtest("admins sudo should require a password"):
        machine.send_chars("sudo -n true || echo 'pw required admins'\n")
        machine.wait_until_tty_matches(2, "pw required admins")

    login("u1002", 3)

    with subtest("sudo-srv should grant restricted sudo"):
        machine.send_chars("sudo -l -u root id || echo failed5\n")
        machine.wait_until_tty_matches(3, "failed5")
        machine.send_chars("sudo -l -u s-service id || echo failed6\n")
        machine.wait_until_tty_matches(3, "/run/current-system/sw/bin/id")

    with subtest("sudo-srv should be able to become service user without password"):
        machine.send_chars("sudo -niu s-service\n")
        machine.wait_until_tty_matches(3, 's-service@machine')

    with subtest("sudo-srv should be able to run systemctl without password"):
        machine.send_chars("sudo -n systemctl --no-pager && echo 'pw not required systemctl'\n")
        machine.wait_until_tty_matches(3, "pw not required systemctl")

    with subtest("sudo-srv should be able to run fc-manage without password"):
        machine.send_chars("sudo -n fc-manage && echo 'pw not required fc-manage'\n")
        machine.wait_until_tty_matches(3, "pw not required fc-manage")

    with subtest("sudo-srv user should be able to run iotop without password"):
        machine.send_chars("sudo -n iotop -n1 && echo 'pw not required iotop'\n")
        machine.wait_until_tty_matches(3, "pw not required iotop")

    login("u1003", 4)

    with subtest("wheel sudo should require a password"):
        machine.send_chars("sudo -n true || echo 'pw required wheel'\n")
        machine.wait_until_tty_matches(4, "pw required wheel")

    login("u1004", 5)

    with subtest("wheel+sudo-srv should be able to use service user without password"):
        machine.send_chars("sudo -l -u s-service id || echo failed7\n")
        machine.wait_until_tty_matches(5, "/run/current-system/sw/bin/id")

    login("s-service", 6)

    with subtest("service user should be able to run systemctl without password"):
        machine.send_chars("sudo -n systemctl --no-pager && echo 'pw not required systemctl'\n")
        machine.wait_until_tty_matches(6, "pw not required systemctl")

    with subtest("service user should be able to run fc-manage without password"):
        machine.send_chars("sudo -n fc-manage  && echo 'pw not required fc-manage'\n")
        machine.wait_until_tty_matches(6, "pw not required fc-manage")

    with subtest("service user should be able to run iotop without password"):
        machine.send_chars("sudo -n iotop -n1 && echo 'pw not required iotop'\n")
        machine.wait_until_tty_matches(6, "pw not required iotop")

    with subtest("service user should be able to run ipXtables without password"):
        machine.send_chars("sudo -n iptables && echo 'pw not required iptables'\n")
        machine.wait_until_tty_matches(6, "pw not required iptables")

        machine.send_chars("sudo -n ip6tables && echo 'pw not required ip6tables'\n")
        machine.wait_until_tty_matches(6, "pw not required ip6tables")
  '';
})
