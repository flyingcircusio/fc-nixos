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
        ../nixos ../nixos/roles
      ];

      flyingcircus.users = {
        userData = userData;
        permissions = [
          {
            id = 2028;
            name = "sudo-srv";
          }
        ];
      };

      flyingcircus.enc.parameters.resource_group = "test";

      services.telegraf.enable = false;

    };

  testScript = ''
    machine.wait_for_unit('multi-user.target')

    def assert_id_output(uid, gid, groups, id_output):
        actual_uid, actual_gid, actual_groups = id_output.strip().split()
        assert actual_uid == f"uid={uid}", f"uid: expected {uid}, got {actual_uid}"
        assert actual_gid == f"gid={gid}", f"gid: expected {gid}, got {actual_gid}"
        # Group order is not fixed!
        actual_groups = set(actual_groups.removeprefix("groups=").split(","))
        groups = set(groups.split(","))
        assert actual_groups == groups, f"groups: expected: {groups}, got {actual_groups}"

    with subtest("check uids"):
        out = machine.succeed("id u1000")
        assert_id_output("1000(u1000)", "100(users)", "100(users)", out)
        out = machine.succeed("id u1001")
        assert_id_output("1001(u1001)", "100(users)", "100(users),2003(admins)", out)
        out = machine.succeed("id u1002")
        assert_id_output("1002(u1002)", "100(users)", "100(users),503(sudo-srv)", out)
        out = machine.succeed("id u1003")
        assert_id_output("1003(u1003)", "100(users)", "100(users),1(wheel)", out)
        out = machine.succeed("id u1004")
        assert_id_output("1004(u1004)", "100(users)", "100(users),1(wheel),503(sudo-srv)", out)
        out = machine.succeed("id s-service")
        assert_id_output("1074(s-service)", "900(service)", "900(service)", out)

    def login(user: str, tty: str):
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

    login("u1000", "1")

    with subtest("unprivileged user should not be able to sudo"):
        machine.send_chars("sudo -l -u root id || echo failed1\n")
        machine.wait_until_tty_matches("1", "failed1")
        machine.send_chars("sudo -l -u s-service id || echo failed2\n")
        machine.wait_until_tty_matches("1", "failed2")

    with subtest("unprivileged user should be able to run ipXtables without password"):
        machine.send_chars("sudo -n iptables && echo 'pw not required iptables'\n")
        machine.wait_until_tty_matches("1", "pw not required iptables")

        machine.send_chars("sudo -n ip6tables && echo 'pw not required ip6tables'\n")
        machine.wait_until_tty_matches("1", "pw not required ip6tables")

    login("u1001", "2")

    with subtest("admins should be able to sudo"):
        machine.send_chars("sudo -l -u root id || echo failed3\n")
        machine.wait_until_tty_matches("2", "/run/current-system/sw/bin/id")
        machine.send_chars("sudo -l -u s-service id || echo failed4\n")
        machine.wait_until_tty_matches("2", "/run/current-system/sw/bin/id")

    with subtest("admins sudo should require a password"):
        machine.send_chars("sudo -n true || echo 'pw required admins'\n")
        machine.wait_until_tty_matches("2", "pw required admins")

    login("u1002", "3")

    with subtest("sudo-srv should grant restricted sudo"):
        machine.send_chars("sudo -l -u root id || echo failed5\n")
        machine.wait_until_tty_matches("3", "failed5")
        machine.send_chars("sudo -l -u s-service id || echo failed6\n")
        machine.wait_until_tty_matches("3", "/run/current-system/sw/bin/id")

    with subtest("sudo-srv should be able to become service user without password"):
        machine.send_chars("sudo -niu s-service\n")
        machine.wait_until_tty_matches("3", 's-service@machine')

    with subtest("sudo-srv should be able to run systemctl without password"):
        machine.send_chars("sudo -n systemctl --no-pager && echo 'pw not required systemctl'\n")
        machine.wait_until_tty_matches("3", "pw not required systemctl")

    with subtest("sudo-srv should be able to run fc-manage without password"):
        machine.send_chars("sudo -n fc-manage && echo 'pw not required fc-manage'\n")
        machine.wait_until_tty_matches("3", "pw not required fc-manage")

    with subtest("sudo-srv user should be able to run iotop without password"):
        machine.send_chars("sudo -n iotop -n1 && echo 'pw not required iotop'\n")
        machine.wait_until_tty_matches("3", "pw not required iotop")

    login("u1003", "4")

    with subtest("wheel sudo should require a password"):
        machine.send_chars("sudo -n true || echo 'pw required wheel'\n")
        machine.wait_until_tty_matches("4", "pw required wheel")

    login("u1004", "5")

    with subtest("wheel+sudo-srv should be able to use service user without password"):
        machine.send_chars("sudo -l -u s-service id || echo failed7\n")
        machine.wait_until_tty_matches("5", "/run/current-system/sw/bin/id")

    login("s-service", "6")

    with subtest("service user should be able to run systemctl without password"):
        machine.send_chars("sudo -n systemctl --no-pager && echo 'pw not required systemctl'\n")
        machine.wait_until_tty_matches("6", "pw not required systemctl")

    with subtest("service user should be able to run fc-manage without password"):
        machine.send_chars("sudo -n fc-manage  && echo 'pw not required fc-manage'\n")
        machine.wait_until_tty_matches("6", "pw not required fc-manage")

    with subtest("service user should be able to run iotop without password"):
        machine.send_chars("sudo -n iotop -n1 && echo 'pw not required iotop'\n")
        machine.wait_until_tty_matches("6", "pw not required iotop")

    with subtest("service user should be able to run ipXtables without password"):
        machine.send_chars("sudo -n iptables && echo 'pw not required iptables'\n")
        machine.wait_until_tty_matches("6", "pw not required iptables")

        machine.send_chars("sudo -n ip6tables && echo 'pw not required ip6tables'\n")
        machine.wait_until_tty_matches("6", "pw not required ip6tables")
  '';
})
