import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:

with lib;
with testlib;

{
  name = "filebeat";

  nodes = {
    unconfigured =
      { pkgs, ... }: {
        imports = [
          (fcConfig { id = 2; })
        ];

        # We provide a target but no input, so filebeats do not get enabled.
        flyingcircus.beats.logTargets.localhost = {
          host = "127.0.0.1"; port= 9002;
        };

        systemd.services.netcatgraylog = {
            wantedBy = [ "multi-user.target" ];
            script = ''
            ${pkgs.netcat}/bin/nc -lvt 127.0.0.1 9002
            '';
        };

      };

    configured =
      { ... }: {
        imports = [
          (fcConfig { id = 1; })
        ];

        config = {
          flyingcircus.beats.logTargets.localhost = {
            host = "127.0.0.1"; port= 9002;
          };

          systemd.services.netcatgraylog = {
              wantedBy = [ "multi-user.target" ];
              script = ''
              ${pkgs.netcat}/bin/nc -lvt 127.0.0.1 9002
              '';
          };

          flyingcircus.filebeat.inputs.lastlog = {
            enabled = true;
            type = "log";
            paths = [ "/var/log/lastlog" ];
          };

        };
      };
  };
  testScript = ''
    start_all()

    status = unconfigured.execute('systemctl status filebeat-localhost')[1]
    print(status)
    assert "Unit filebeat-localhost.service is masked." in status

    configured.wait_for_unit('multi-user.target')
    status = configured.execute('systemctl status filebeat-localhost')[1]
    print(status)
    assert "status=0/SUCCESS" in status

  '';
})
