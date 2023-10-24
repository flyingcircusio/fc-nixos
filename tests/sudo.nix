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
  enableOCR = true;
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
    };

  testScript = ''
    machine.wait_for_unit('multi-user.target')

    def assert_id_output(uid: str, gid: str, groups_str: str, id_output: str):
        actual_uid, actual_gid, actual_groups_str = id_output.strip().split()
        assert actual_uid == f"uid={uid}", f"uid: expected {uid}, got {actual_uid}"
        assert actual_gid == f"gid={gid}", f"gid: expected {gid}, got {actual_gid}"
        # Group order is not fixed!
        actual_groups = set(actual_groups_str.removeprefix("groups=").split(","))
        groups = set(groups_str.split(","))
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


    def assert_can_sudo(user: str, command: str, *, run_as="root"):
      machine.succeed(f"sudo -u {user} sudo -u {run_as} -l {command}")

    def assert_cannot_sudo(user: str, command: str, *, run_as="root"):
      machine.fail(f"sudo -u {user} sudo -u {run_as} -l {command}")

    def assert_no_password_required(user: str, command: str, *, run_as="root"):
      machine.succeed(f"sudo -u {user} sudo -n -u {run_as} {command}")

    def assert_password_required(user: str, command: str, *, run_as="root"):
      machine.fail(f"sudo -u {user} sudo -n -u {run_as} {command}")



    with subtest("unprivileged user should not be able to sudo"):
        assert_cannot_sudo("u1000", "id")
        assert_cannot_sudo("u1000", "id", run_as="s-service")

    with subtest("unprivileged user should not be able to run ipXtables"):
        assert_cannot_sudo("u1000", "iptables")
        assert_cannot_sudo("u1000", "ip6tables")


    with subtest("admins should be able to sudo"):
        assert_can_sudo("u1001", "id")
        assert_can_sudo("u1001", "id", run_as="s-service")

    with subtest("admins sudo should require a password"):
        assert_password_required("u1001", "true")


    with subtest("sudo-srv should grant restricted sudo"):
        assert_cannot_sudo("u1002", "id")
        assert_can_sudo("u1002", "id", run_as="s-service")



    with subtest("sudo-srv should be able to run systemctl without password"):
        assert_no_password_required("u1002", "systemctl --no-pager")

    with subtest("sudo-srv should be able to run fc-manage without password"):
        assert_no_password_required("u1002", "fc-manage")

    with subtest("sudo-srv user should be able to run iotop without password"):
        assert_no_password_required("u1002", "iotop -n1")


    with subtest("wheel sudo should require a password"):
        assert_password_required("u1003", "true")


    with subtest("wheel+sudo-srv should be able to use service user without password"):
        assert_no_password_required("u1004", "id", run_as="s-service")


    with subtest("service user should be able to run systemctl without password"):
        assert_no_password_required("s-service", "systemctl --no-pager")

    with subtest("service user should be able to run fc-manage without password"):
        assert_no_password_required("s-service", "fc-manage")

    with subtest("service user should be able to run iotop without password"):
        assert_no_password_required("s-service", "iotop -n1")

    with subtest("service user should be able to run ipXtables without password"):
        assert_no_password_required("s-service", "iptables -L")
        assert_no_password_required("s-service", "ip6tables -L")


    # Inspect tty contents in the interactive test driver with:
    # print(machine.get_tty_text(1)

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

    login("u1002", "1")

    with subtest("sudo-srv should be able to become service user without password"):
        machine.send_chars("sudo -niu s-service\n")
        machine.wait_until_tty_matches("1", 's-service@machine')
  '';
})
