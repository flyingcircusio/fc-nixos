import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:

with lib;
with testlib;

{
  name = "audit";

  nodes = {
    client = # this is simply a client that will ssh into the server
      { pkgs, ... }: {
        imports = [
          (fcConfig { id = 1; })
        ];

        config = {
          environment.systemPackages = with pkgs; [
            openssh
          ];

          environment.etc = {
            "ssh_key" = {
              text = testkey.priv;
              mode = "0400";
            };
            "ssh_key.pub" = {
              text = testkey.pub;
              mode = "0400";
            };
          };
        };
      };

    /* loghost =
      { ... }: {
        imports = [
          (fcConfig { id = 2; })
        ];

        config = {
          virtualisation.memorySize = 4096;

          flyingcircus.roles.loghost.enable = true;
          flyingcircus.roles.graylog.publicFrontend = {
            enable = true;
            hostName="loghost.fcio.net";
          };

          networking.hosts."::1" = [ "loghost.fcio.net" ];

          flyingcircus.roles.elasticsearch.heapPercentage = 30;
          flyingcircus.services.graylog.heapPercentage = 35;

          networking.domain = "fcio.net";

          systemd.services = {
            "acme-loghost.fcio.net" = {
              script = mkForce "true";
            };
          };
        };
      }; */

    server =
      { ... }: {
        imports = [
          (fcConfig { id = /* 3 */ 2; })
        ];

        config = {
          virtualisation.memorySize = 2048;

          services.openssh.enable = mkForce true;
          flyingcircus.audit.enable = true;

          users.users.customer = {
            isNormalUser = true;
            group = "users";
            openssh.authorizedKeys.keys = [
              testkey.pub
            ];
            hashedPassword = "";
            extraGroups = [ "login" "wheel" ];
          };

          /* flyingcircus.beats.logTargets.loghost = {
            host = fcIP.srv4 2;
            port = 9002;
          }; */

          users.groups.login = {};

          security.sudo.wheelNeedsPassword = false;
        };
      };
  };
  testScript = ''
    from shlex import quote
    import json

    # first boot loghost to ensure graylog is ready when other VMs boot
    # loghost.wait_for_unit('multi-user.target')

    # then boot the rest
    start_all()
    client.wait_for_unit('multi-user.target')
    server.wait_for_unit('auditbeat')
    server.wait_for_unit('multi-user.target')

    def ssh(cmd):
      client.succeed("ssh -oStrictHostKeyChecking=no customer@${fcIP.fe4 2} -i/etc/ssh_key " + cmd)

    def beatgrep(fnc):
      _, out = server.execute("cat /var/lib/auditbeat/auditbeat")

      for line in out.split("\n"):
        try:
          if fnc(json.loads(line)):
            return True
        except Exception as e:
          print(e)

      raise Exception("Failed to find matching auditbeat line")

    # with subtest("check if events are being transferred to loghost"):
    #  loghost.wait_until_succeeds("curl -v -k https://loghost.fcio.net | grep -q 'Graylog Web Interface'")
    #  client.wait_for_unit("auditbeat")
    #  client.wait_for_unit("filebeat-loghost")
    #  client.wait_for_unit("journalbeat-loghost")

    def _keystrokes(obj):
      return obj["auditd"]["summary"]["object"]["type"] == "keystrokes"

    with subtest("check if ssh connection is logged by auditbeat"):
      ssh("true")
      beatgrep(_keystrokes)

    def _sudo(obj):
      return obj["auditd"]["summary"]["how"].endswith("sshd") and obj["audit"]["summary"]["actor"]["primary"] == "customer"

    with subtest("check if sudo is logged by auditbeat"):
      ssh("sudo true")
      beatgrep(_sudo)
  '';
})
