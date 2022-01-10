import ./make-test-python.nix ({ lib, ... }:

{
  name = "users";
  machine =
    { pkgs, lib, config, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];

      flyingcircus.enc.parameters.interfaces.srv = {
        mac = "52:54:00:12:34:56";
        bridged = false;
        networks = {
          "192.168.101.0/24" = [ "192.168.101.1" ];
          "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
        };
        gateways = {};
      };

      users.users =
        lib.mapAttrs'
          (id: groups:
            lib.nameValuePair
              "u${id}"
              {
                uid = builtins.fromJSON id;
                extraGroups = groups;
                isNormalUser = true;
                name = "u${id}";
                hashedPassword = "*";
              }
          )
          {
            "1000" = [ ];
            "1001" = [ "login" ];
            "1002" = [ "manager" ];
            "1003" = [ "sudo-srv" ];
            "1004" = [ "wheel" ];
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

    cmp(set(get("ls /etc/local/htpasswd*").split()), {
      '/etc/local/htpasswd_fcio_users',
      '/etc/local/htpasswd_fcio_users.login',
      '/etc/local/htpasswd_fcio_users.manager',
      '/etc/local/htpasswd_fcio_users.sudo-srv',
      '/etc/local/htpasswd_fcio_users.wheel'})

    assert get("cat /etc/local/htpasswd_fcio_users.login") == "u1001:*"
    assert get("cat /etc/local/htpasswd_fcio_users.manager")== "u1002:*"
    assert get("cat /etc/local/htpasswd_fcio_users.sudo-srv") == "u1003:*"
    assert get("cat /etc/local/htpasswd_fcio_users.wheel")== "u1004:*"
  '';
})
