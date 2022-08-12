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
              mode = "0444";
            };
            "ssh_key.pub" = {
              text = testkey.pub;
              mode = "0444";
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

          flyingcircus.beats.logTargets.localhost = {
            host = "127.0.0.1"; port= 9002;
          };
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

          users.groups.login = {};

          security.sudo.wheelNeedsPassword = false;

          systemd.services.netcatgraylog = {
              wantedBy = [ "multi-user.target" ];
              script = ''
              ${pkgs.netcat}/bin/nc -lvt 127.0.0.1 9002
              '';
          };

        };
      };
  };
  testScript = replaceStrings ["__SERVERIP__"] [(fcIP.fe4 2)] (readFile ./audit.py);
})
