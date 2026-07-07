import ./make-test-python.nix (
  {
    pkgs,
    lib,
    testlib,
    ...
  }:

  with lib;
  with testlib;

  {
    name = "wazuh-agent";

    nodes = {
      configured =
        { pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig { id = 1; })
          ];

          # Generate self-signed cert for fake manager SSL on port 1515.
          systemd.services.wazuh-fake-manager-certs = {
            description = "Generate self-signed cert for fake Wazuh manager";
            before = [ "wazuh-fake-manager.service" ];
            wantedBy = [ "wazuh-fake-manager.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.writeShellScript "gen-certs" ''
                mkdir -p /var/lib/wazuh-fake-manager
                ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -keyout /var/lib/wazuh-fake-manager/server.key -out /var/lib/wazuh-fake-manager/server.crt -days 1 -nodes -subj '/CN=localhost'
                chmod 600 /var/lib/wazuh-fake-manager/server.key
              ''}";
            };
          };

          # Fake Wazuh manager - accepts connections on ports 1514/1515
          # so agent-auth can complete enrollment.
          #
          # Tied to wazuh-agent-auth.service (not multi-user.target)
          # because wazuh-agent-auth starts as part of wazuh.target,
          # which is pulled in during the multi-user activation wave.
          # If the fake manager were wantedBy multi-user.target, it
          # would race with agent-auth and lose — the Before= only
          # orders services that are *both* in the start queue.
          systemd.services.wazuh-fake-manager = {
            description = "Fake Wazuh Manager for Testing";
            after = [
              "network.target"
              "wazuh-fake-manager-certs.service"
            ];
            before = [ "wazuh-agent-auth.service" ];
            wantedBy = [ "wazuh-agent-auth.service" ];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "fake-manager.py" ''
                import socket
                import ssl
                import sys
                import threading

                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(
                  "/var/lib/wazuh-fake-manager/server.crt",
                  "/var/lib/wazuh-fake-manager/server.key",
                )

                def handle_enrollment(conn):
                    """Handle one enrollment connection."""
                    try:
                        conn.settimeout(30)
                        # Read the client enrollment message (OSSEC PASS: ... OSSEC A:'...')
                        data = b""
                        while b"\n" not in data:
                            chunk = conn.recv(4096)
                            if not chunk:
                                return
                            data += chunk
                        # Send enrollment response: OSSEC K:'<id> <name> <ip> <key>'
                        # Key must pass OS_IsValidName: alnum/-/_ only, no '='
                        # 33 bytes base64 = 44 chars, no padding
                        conn.sendall(b"OSSEC K:'001 configured 127.0.0.1 QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFB'\n")
                        # Graceful shutdown: wait for client to read
                        conn.settimeout(5)
                        try:
                            conn.recv(4096)
                        except (socket.timeout, Exception):
                            pass
                    except Exception as e:
                        print(f"Enrollment handler error: {e}", file=sys.stderr, flush=True)
                    finally:
                        try:
                            conn.shutdown(socket.SHUT_RDWR)
                        except Exception:
                            pass
                        conn.close()

                def accept_loop(port):
                    """Accept connections on a port, handle enrollment on 1515."""
                    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    s.bind(("0.0.0.0", port))
                    s.listen(5)
                    print(f"Fake manager listening on port {port}", file=sys.stderr, flush=True)
                    while True:
                        conn_plain, addr = s.accept()
                        print(f"Connection from {addr} on port {port}", file=sys.stderr, flush=True)
                        if port == 1515:
                            try:
                                conn = context.wrap_socket(conn_plain, server_side=True)
                                threading.Thread(target=handle_enrollment, args=(conn,), daemon=True).start()
                            except Exception as e:
                                print(f"SSL wrap error: {e}", file=sys.stderr, flush=True)
                                conn_plain.close()
                        else:
                            conn_plain.close()

                threads = []
                for port in [1514, 1515]:
                    t = threading.Thread(target=accept_loop, args=(port,), daemon=True)
                    t.start()
                    threads.append(t)

                # Keep main thread alive
                try:
                    for t in threads:
                        t.join()
                except KeyboardInterrupt:
                    pass
              ''}";
            };
          };

          flyingcircus.roles.wazuh-agent = {
            enable = true;
            managerAddress = "127.0.0.1";
            agentAuthPassword = "test-password";
          };

          # Retry enrollment until fake manager is ready.
          systemd.services.wazuh-agent-auth.serviceConfig = {
            Restart = "on-failure";
            RestartSec = "1";
            StartLimitIntervalSec = 60;
          };
        };

      unconfigured =
        { pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig { id = 2; })
          ];
          # wazuh-agent not enabled — should have no wazuh services
        };

      # Verifies that the FC role's defaults survive user customization:
      #  - scalar overrides via services.wazuh.agent.settings.* (mkDefault per leaf)
      #  - list EXTENSION via direct settings.* assignment (auto-concatenation:
      #    the freeformType from pkgs.formats.xml concatenates list definitions
      #    at equal priority instead of replacing them)
      override =
        { pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig { id = 3; })
          ];

          flyingcircus.roles.wazuh-agent = {
            enable = true;
            managerAddress = "127.0.0.1";
            agentAuthPassword = "test-password";
          };

          # Scalar override — only this value changes, all other role
          # defaults survive (mkDefault per leaf).
          services.wazuh.agent.settings.client.notify_time = 30;

          # Direct list assignments — the freeformType auto-concatenates
          # these with the role defaults, so /etc/local and journald survive.
          services.wazuh.agent.settings.syscheck.directories = [ "/srv/app" ];
          services.wazuh.agent.settings.localfile = [
            {
              location = "/var/log/test";
              log_format = "syslog";
            }
          ];
        };
    };

    testScript = ''
      import xml.etree.ElementTree as ET


      def debug_print(machine, cmd):
          rc, output = machine.execute(cmd)
          print(f"=== {cmd} (rc={rc}) ===")
          print(output)
          return rc, output


      start_all()

      # --- Configured node tests ---
      configured.wait_for_unit("multi-user.target")

      # 1. setup-pre-wazuh.service succeeded
      configured.succeed("systemctl show setup-pre-wazuh.service --property=Result | grep success")

      # 2. /var/ossec directory structure exists
      configured.succeed("test -d /var/ossec")
      configured.succeed("test -d /var/ossec/etc")
      configured.succeed("test -d /var/ossec/bin")
      configured.succeed("test -d /var/ossec/queue")
      configured.succeed("test -d /var/ossec/logs")

      # 3. ossec.conf exists and is valid XML (NOT a symlink)
      configured.succeed("test -f /var/ossec/etc/ossec.conf")
      rc, link = configured.execute("readlink /var/ossec/etc/ossec.conf")
      assert rc != 0 or link == "", f"ossec.conf is a symlink: {link}"
      xml_content = configured.succeed("cat /var/ossec/etc/ossec.conf")
      ET.fromstring(xml_content)

      # 4. wazuh user/group exist
      configured.succeed("id wazuh")
      rc, grp = configured.execute("getent group wazuh")
      assert rc == 0, f"wazuh group missing: {grp}"

      # 5. All 5 daemon services are active
      for daemon in [
          "wazuh-modulesd",
          "wazuh-logcollector",
          "wazuh-syscheckd",
          "wazuh-agentd",
          "wazuh-execd",
      ]:
          configured.succeed(f"systemctl is-active {daemon}.service")

      # 6. Password file exists with correct owner (permissions are 750 due to upstream find -exec chmod)
      configured.succeed("test -f /var/ossec/etc/authd.pass")
      rc, owner = configured.execute("stat -c '%U:%G' /var/ossec/etc/authd.pass")
      assert owner.strip() == "wazuh:wazuh", f"Expected wazuh:wazuh, got {owner}"

      # 7. Config contains the manager address
      conf = configured.succeed("cat /var/ossec/etc/ossec.conf")
      assert "127.0.0.1" in conf, "Manager address 127.0.0.1 not found in ossec.conf"

      # 8. wazuh.target is active
      configured.succeed("systemctl is-active wazuh.target")

      # 9. wazuh-agent-auth completed successfully (enrollment)
      configured.succeed("systemctl show wazuh-agent-auth.service --property=Result | grep success")

      # 10. .agent-registered marker file created by wazuh-agent-auth
      configured.succeed("test -f /var/ossec/.agent-registered")

      # --- Unconfigured node tests ---
      unconfigured.wait_for_unit("multi-user.target")

      # 1. No wazuh services exist
      for daemon in [
          "wazuh-modulesd",
          "wazuh-logcollector",
          "wazuh-syscheckd",
          "wazuh-agentd",
          "wazuh-execd",
          "setup-pre-wazuh",
          "wazuh-agent-auth",
      ]:
          rc, _ = unconfigured.execute(f"systemctl is-active {daemon}.service")
          assert rc != 0, f"{daemon} should not exist on unconfigured node"

      # 2. No /var/ossec directory
      rc, _ = unconfigured.execute("test -d /var/ossec")
      assert rc != 0, "/var/ossec should not exist on unconfigured node"

      # --- Override node: verify role defaults survive user customization ---
      # setup-pre-wazuh writes ossec.conf from the merged settings — no
      # enrollment or fake manager needed. Note: setup-pre is Type=oneshot,
      # so it's inactive (dead) after success — check Result, not active state.
      override.wait_until_succeeds(
          "systemctl show setup-pre-wazuh.service --property=Result | grep success"
      )

      override_conf = override.succeed("cat /var/ossec/etc/ossec.conf")
      root = ET.fromstring(override_conf)

      def text_of(tag):
          el = root.find(f".//{tag}")
          return el.text if el is not None else None

      # 1. Scalar override applied: notify_time = 30 (role default was 20)
      nt = text_of("notify_time")
      assert nt == "30", f"user override notify_time=30 not applied, got {nt!r}"

      # 2. List auto-concatenation: direct /srv/app assignment added
      dirs = [el.text for el in root.findall(".//directories")]
      assert "/srv/app" in dirs, f"direct assignment /srv/app missing, got {dirs!r}"

      # 3. Default directory survived: /etc/local still present (auto-concat, not replace)
      assert "/etc/local" in dirs, f"default /etc/local lost after direct assignment, got {dirs!r}"

      # 4. List auto-concatenation: direct localfile assignment added
      locations = [el.text for el in root.findall(".//localfile/location")]
      assert "/var/log/test" in locations, f"direct localfile /var/log/test missing, got {locations!r}"

      # 5. Default localfile survived: journald still present (auto-concat, not replace)
      assert "journald" in locations, f"default journald localfile lost after direct assignment, got {locations!r}"

      # 6. Untouched role defaults survived the scalar override
      qs = text_of("queue_size")
      assert qs == "5000", f"role default queue_size=5000 lost, got {qs!r}"

      cm = text_of("crypto_method")
      assert cm == "aes", f"role default crypto_method=aes lost, got {cm!r}"

      addr = text_of("address")
      assert addr == "127.0.0.1", f"role default managerAddress lost, got {addr!r}"
    '';
  }
)
