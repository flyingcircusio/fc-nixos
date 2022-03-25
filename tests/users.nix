import ./make-test-python.nix ({ lib, testlib, ... }:

{
  name = "users";
  machine =
    { pkgs, lib, config, ... }:
    let
      userData =
        (lib.mapAttrsToList (id: groups: {
          class = "human";
          gid = 100;
          home_directory = "/home/u${id}";
          id = builtins.fromJSON id;
          login_shell = "/bin/bash";
          name = "Human User";
          password = "*";
          permissions.test = groups;
          ssh_pubkey = [];
          uid = "u${id}";
        })
        {
          "1000" = [ ];
          "1001" = [ "login" ];
          "1002" = [ "manager" ];
          "1003" = [ "sudo-srv" ];
          "1004" = [ "wheel" ];
        }) ++ [
          {
            class = "service";
            gid = 101;
            home_directory = "/srv/s-service";
            id = 1074;
            login_shell = "/bin/bash";
            name = "s-service";
            password = "*";
            permissions.test = [];
            ssh_pubkey = [];
            uid = "s-service";
          }
        ];
      in
      {
        imports = [
          (testlib.fcConfig {
            extraEncParameters = { resource_group = "test"; };
          })
        ];

        flyingcircus.users = {
          userData = userData;
        };

      };

  testScript = ''
    machine.wait_for_unit('multi-user.target')

    def get(cmd):
      print(f"$ {cmd}")
      _, result = machine.execute(cmd)
      print(result)
      return result

    def cmp(a, b):
      if a == b:
        return
      print("Comparison failed")
      print(a)
      print(" != ")
      print(b)
      raise AssertionError()

    def assert_permissions(expected, path):
      permissions = machine.succeed(f"stat {path} -c %a:%U:%G").strip()
      print(f"{path}: {permissions}")
      assert permissions == expected, f"expected: {expected}, got {permissions}"

    with subtest("Common and group-specific htpasswd files should be present"):
      cmp(set(get("ls /etc/local/htpasswd*").split()), {
        '/etc/local/htpasswd_fcio_users',
        '/etc/local/htpasswd_fcio_users.login',
        '/etc/local/htpasswd_fcio_users.manager',
        '/etc/local/htpasswd_fcio_users.sudo-srv',
        '/etc/local/htpasswd_fcio_users.wheel'})

    with subtest("Group-specific htpasswd should contain the right users"):
      assert get("cat /etc/local/htpasswd_fcio_users.login") == "u1001:*"
      assert get("cat /etc/local/htpasswd_fcio_users.manager")== "u1002:*"
      assert get("cat /etc/local/htpasswd_fcio_users.sudo-srv") == "u1003:*"
      assert get("cat /etc/local/htpasswd_fcio_users.wheel")== "u1004:*"

    with subtest("Home dirs should exist and have correct permissions"):
      assert_permissions("755:u1000:users", "/home/u1000")
      assert_permissions("755:s-service:service", "/srv/s-service")
  '';
})
