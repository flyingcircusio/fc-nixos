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

          # Fake Wazuh manager — listens on 1514/1515 so agent-auth can enroll.
          #
          # Start wiring (why wantedBy targets agent-auth, not multi-user.target):
          #   1. before=/after= only order units within the SAME start transaction.
          #   2. agent-auth is pulled in via multi-user.target -> wazuh.target; a
          #      manager wanted by multi-user.target would take a separate pull-in
          #      path and could land in a different transaction — unordered, it
          #      races a manager that isn't listening yet (connection refused).
          #   3. wantedBy = agent-auth pulls the manager into EVERY transaction
          #      that starts agent-auth (boot, restart, manual start), ordered
          #      first via before=. The pair cannot end up in separate queues.
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
              ExecStart = pkgs.writers.writePython3 "fake-manager.py" { } ''
                import socket
                import ssl
                import sys
                import threading
                import time

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
                        key = b"QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFB"
                        response = (
                            b"OSSEC K:'001 configured 127.0.0.1 "
                            + key
                            + b"'\n"
                        )
                        conn.sendall(response)
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
                    print(
                        f"Fake manager listening on port {port}",
                        file=sys.stderr,
                        flush=True,
                    )
                    while True:
                        conn_plain, addr = s.accept()
                        print(
                            f"Connection from {addr} on port {port}",
                            file=sys.stderr,
                            flush=True,
                        )
                        if port == 1515:
                            try:
                                conn = context.wrap_socket(conn_plain, server_side=True)
                                threading.Thread(
                                    target=handle_enrollment,
                                    args=(conn,),
                                    daemon=True,
                                ).start()
                            except Exception as e:
                                print(f"SSL wrap error: {e}", file=sys.stderr, flush=True)
                                conn_plain.close()
                        else:
                            conn_plain.close()


                # Bind late on purpose: the first agent-auth attempts hit a
                # closed port, forcing a real enrollment retry cycle
                # (Restart=on-failure + RestartSec=5s on wazuh-agent-auth).
                time.sleep(10)

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
              '';
            };
          };

          flyingcircus.roles.wazuh-agent = {
            enable = true;
            managerAddress = "127.0.0.1";
            agentAuthPassword = "test-password";
          };

          # Config-change scenario for the testScript: switching to this
          # specialisation must update ossec.conf and restart the daemons
          # (restartTriggers on the generated config).
          specialisation.restartConfig.configuration = {
            services.wazuh.agent.settings.client.notify_time = 30;
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
      import re
      import xml.etree.ElementTree as ET

      start_all()

      # --- Configured node tests ---
      configured.wait_for_unit("multi-user.target")

      # 1. setup-pre-wazuh.service succeeded
      configured.succeed("systemctl show setup-pre-wazuh.service --property=Result | grep success")

      # 2. ossec.conf exists and is valid XML (NOT a symlink)
      configured.succeed("test -f /var/ossec/etc/ossec.conf")
      rc, link = configured.execute("readlink /var/ossec/etc/ossec.conf")
      assert rc != 0 or link == "", f"ossec.conf is a symlink: {link}"
      xml_content = configured.succeed("cat /var/ossec/etc/ossec.conf")
      ET.fromstring(xml_content)

      # 3. wazuh user/group exist
      configured.succeed("id wazuh")
      rc, grp = configured.execute("getent group wazuh")
      assert rc == 0, f"wazuh group missing: {grp}"
      # Journal/network access is granted per-service (SupplementaryGroups
      # on the daemon services), not user-wide.
      id_out = configured.succeed("id wazuh")
      assert "systemd-journal" not in id_out, f"wazuh user in systemd-journal: {id_out}"
      assert "systemd-network" not in id_out, f"wazuh user in systemd-network: {id_out}"

      # 4. All 5 daemons run with the per-daemon journal group and
      # capability separation from the daemons table in
      # nixos/services/wazuh/agent.nix.
      JOURNAL_GID = configured.succeed("getent group systemd-journal").split(":")[2]
      # CapEff masks: CAP_DAC_READ_SEARCH = bit 2 (0x004),
      # CAP_NET_BIND_SERVICE = bit 10 (0x400)
      expected = {
          "wazuh-modulesd": {"journal": False, "caps": "0000000000000004"},
          "wazuh-logcollector": {"journal": True, "caps": "0000000000000004"},
          "wazuh-syscheckd": {"journal": False, "caps": "0000000000000404"},
          "wazuh-agentd": {"journal": False, "caps": "0000000000000000"},
          "wazuh-execd": {"journal": False, "caps": "0000000000000000"},
      }
      for daemon, exp in expected.items():
          # Process-level proof: the daemon's real credentials in
          # /proc/<pid>/status carry exactly the intended groups and
          # effective capabilities — not just the unit definition.
          pid = configured.succeed(
              f"systemctl show {daemon}.service --property=MainPID --value"
          ).strip()
          assert pid != "0", f"{daemon}.service has no MainPID"
          groups_line = ""
          cap_line = ""
          for line in configured.succeed(f"cat /proc/{pid}/status").splitlines():
              if line.startswith("Groups:"):
                  groups_line = line
              if line.startswith("CapEff:"):
                  cap_line = line
          assert groups_line, f"no Groups: line for {daemon} pid {pid}"
          assert cap_line, f"no CapEff: line for {daemon} pid {pid}"
          pid_gids = groups_line.split()[1:]
          if exp["journal"]:
              assert JOURNAL_GID in pid_gids, (
                  f"{daemon} (pid {pid}) missing journal gid {JOURNAL_GID}: {groups_line}"
              )
          else:
              assert JOURNAL_GID not in pid_gids, (
                  f"{daemon} (pid {pid}) unexpectedly in systemd-journal: {groups_line}"
              )
          cap_eff = cap_line.split()[1]
          assert cap_eff == exp["caps"], (
              f"{daemon} (pid {pid}) CapEff {cap_eff}, expected {exp['caps']}"
          )

      # 4b. Self-healing properties: daemons and agent-auth restart on
      # failure; enrollment retries are unlimited (StartLimitIntervalSec
      # = 0 in [Unit]) because manager outages are external conditions.
      for unit in [
          "wazuh-modulesd",
          "wazuh-logcollector",
          "wazuh-syscheckd",
          "wazuh-agentd",
          "wazuh-execd",
          "wazuh-agent-auth",
      ]:
          restart = configured.succeed(
              f"systemctl show {unit}.service --property=Restart --value"
          ).strip()
          assert restart == "on-failure", f"{unit}.service Restart: {restart}"
          restart_sec = configured.succeed(
              f"systemctl show {unit}.service --property=RestartUSec --value"
          ).strip()
          assert restart_sec == "5s", f"{unit}.service RestartSec: {restart_sec}"
      start_limit = configured.succeed(
          "systemctl show wazuh-agent-auth.service --property=StartLimitIntervalUSec --value"
      ).strip()
      assert start_limit == "0", f"wazuh-agent-auth StartLimitIntervalSec: {start_limit}"

      # 4c. Self-healing OBSERVED: SIGKILL a daemon — systemd must bring it
      # back as a NEW process (Restart=on-failure), not just promise it in
      # the unit config.
      pid_before = configured.succeed(
          "systemctl show wazuh-modulesd.service --property=MainPID --value"
      ).strip()
      configured.succeed("systemctl kill -s SIGKILL wazuh-modulesd.service")
      configured.wait_for_unit("wazuh-modulesd.service")
      pid_after = configured.succeed(
          "systemctl show wazuh-modulesd.service --property=MainPID --value"
      ).strip()
      assert pid_after not in ("", "0", pid_before), (
          f"wazuh-modulesd did not come back as a new process: {pid_before} -> {pid_after}"
      )

      # 5. Password file exists with correct owner and mode 600
      # (written after the tree-wide chmod, so the blanket perms don't touch it)
      configured.succeed("test -f /var/ossec/etc/authd.pass")
      rc, owner = configured.execute("stat -c '%U:%G' /var/ossec/etc/authd.pass")
      assert owner.strip() == "wazuh:wazuh", f"Expected wazuh:wazuh, got {owner}"
      rc, mode = configured.execute("stat -c '%a' /var/ossec/etc/authd.pass")
      assert mode.strip() == "600", f"Expected 600, got {mode}"

      # 5b. Tree permissions from setup-pre-wazuh (chmod -R u=rwX,g=rX,o=):
      # dirs 750, data files 640, executables keep 750, ossec.conf 640 wazuh-owned
      rc, mode = configured.execute("stat -c '%a' /var/ossec/etc")
      assert mode.strip() == "750", f"/var/ossec/etc mode: {mode}"
      rc, perms = configured.execute("stat -c '%a %U:%G' /var/ossec/etc/ossec.conf")
      assert perms.strip() == "640 wazuh:wazuh", f"ossec.conf perms: {perms}"
      rc, mode = configured.execute("stat -c '%a' /var/ossec/bin/agent-auth")
      assert mode.strip() == "750", f"agent-auth mode: {mode}"
      rc, mode = configured.execute("stat -c '%a' /var/ossec/etc/local_internal_options.conf")
      assert mode.strip() == "640", f"local_internal_options.conf mode: {mode}"

      # 6. ossec.conf structure: the manager address sits at its exact
      # schema path, '@'-keys serialize as attributes (pkgs.formats.xml
      # convention the role relies on), and no empty leaf elements exist
      # (Wazuh's parser mishandles <tag></tag> — module filterNulls).
      conf = configured.succeed("cat /var/ossec/etc/ossec.conf")
      root = ET.fromstring(conf)
      assert root.tag == "ossec_config", f"root element: {root.tag}"
      assert root.findtext("client/server/address") == "127.0.0.1", (
          f"client/server/address: {root.findtext('client/server/address')!r}"
      )
      assert root.find("wodle[@name='syscollector']") is not None, (
          "wodle syscollector not serialized with name attribute"
      )
      empty = [el.tag for el in root.iter() if el.text is None and len(el) == 0]
      assert not empty, f"empty elements serialized: {empty}"

      # 6b. Rootcheck database keys are set — rationale in the rootcheck
      # block of nixos/roles/wazuh-agent.nix (no daemon-side default).
      assert root.findtext(".//rootkit_files") is not None, "rootkit_files key missing from ossec.conf"
      assert root.findtext(".//rootkit_trojans") is not None, "rootkit_trojans key missing from ossec.conf"

      # 7. wazuh.target is active
      configured.succeed("systemctl is-active wazuh.target")

      # 8. wazuh-agent-auth completed successfully (enrollment) — despite
      # the fake manager binding its ports only after 10s, so the first
      # attempts were refused and the unit must have retried.
      configured.wait_until_succeeds("systemctl show wazuh-agent-auth.service --property=Result | grep success")
      nrestarts = configured.succeed(
          "systemctl show wazuh-agent-auth.service --property=NRestarts --value"
      ).strip()
      assert int(nrestarts) >= 1, f"wazuh-agent-auth NRestarts: {nrestarts} (expected >= 1)"

      # 8b. Enrollment outcome: the received key landed in client.keys
      # (agent id, name, address, base64 key) — the file agent-auth must
      # be able to write as unprivileged user.
      client_keys = configured.succeed("cat /var/ossec/etc/client.keys")
      assert re.search(r"^001 configured 127\.0\.0\.1 [A-Za-z0-9+/]{44}$", client_keys, re.MULTILINE), (
          f"client.keys does not contain the enrolled key: {client_keys!r}"
      )

      # 9. .agent-registered marker file created by wazuh-agent-auth
      configured.succeed("test -f /var/ossec/.agent-registered")

      # 10. Config change reaches the running daemons: switch to the
      # restartConfig specialisation (notify_time 20 -> 30) and verify
      # ossec.conf is re-copied and every daemon restarted.
      daemons = [
          "wazuh-modulesd",
          "wazuh-logcollector",
          "wazuh-syscheckd",
          "wazuh-agentd",
          "wazuh-execd",
      ]
      pids_before = {}
      for daemon in daemons:
          pid = configured.succeed(
              f"systemctl show {daemon}.service --property=MainPID --value"
          ).strip()
          assert pid != "0", f"{daemon} has no MainPID before switch"
          pids_before[daemon] = pid

      configured.succeed(
          "/run/current-system/specialisation/restartConfig/bin/switch-to-configuration test"
      )

      for daemon in daemons:
          configured.wait_for_unit(f"{daemon}.service")

      conf = configured.succeed("cat /var/ossec/etc/ossec.conf")
      nt = ET.fromstring(conf).findtext(".//notify_time")
      assert nt == "30", f"notify_time=30 not applied after switch, got {nt!r}"

      for daemon in daemons:
          pid = configured.succeed(
              f"systemctl show {daemon}.service --property=MainPID --value"
          ).strip()
          assert pid != "0", f"{daemon} has no MainPID after switch"
          assert pid != pids_before[daemon], (
              f"{daemon} was not restarted by the switch (pid still {pid})"
          )

      # 11. The agent talks to the manager: wazuh-agentd connects to port
      # 1514 — the fake manager logs every accepted connection.
      configured.wait_until_succeeds(
          "journalctl -u wazuh-fake-manager.service | grep 'on port 1514'"
      )

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
