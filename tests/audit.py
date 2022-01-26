import json
import time

start_all()
client.wait_for_unit('multi-user.target')
server.wait_for_unit('auditbeat')
server.wait_for_unit('multi-user.target')

start = time.time()
timeout = 30
while time.time() < start + timeout:
    output = server.execute("cat /var/lib/auditbeat/auditbeat")[1]
    if "@timestamp" in output:
        break
    time.sleep(0.1)
else:
    raise AssertionError("auditbeat not initialized")


def beatgrep(fnc):
    _, out = server.execute("cat /var/lib/auditbeat/auditbeat")
    results = []

    for line in out.split("\n"):
        try:
            obj = json.loads(line)
            match = fnc(obj)
            if match:
                results.append(obj)
        except Exception:
            pass

    if not results:
        raise Exception("Failed to find matching auditbeat line")

    return results


with subtest("Create user and log in"):
    client.wait_for_unit("multi-user.target")
    client.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
    client.succeed("useradd -m alice")
    client.succeed("(echo foobar; echo foobar) | passwd alice")
    client.wait_until_tty_matches(1, "login: ")
    client.send_chars("alice\n")
    client.wait_until_tty_matches(1, "login: alice")
    client.wait_until_succeeds("pgrep login")
    client.wait_until_tty_matches(1, "Password: ")
    client.send_chars("foobar\n")
    client.wait_until_succeeds("pgrep -u alice bash")
    client.screenshot("prompt00")

with subtest("Ensure SSH logins and sudo keystrokes are logged"):
    client.send_chars(
        "ssh -oStrictHostKeyChecking=no customer@__SERVERIP__ -i/etc/ssh_key\n"
    )
    client.wait_until_tty_matches(1, "customer@server")
    client.screenshot("prompt01")
    client.send_chars("ps auxf\n")
    client.screenshot("prompt02")
    client.send_chars("sudo -i\n")
    client.send_chars("rm /tmp/asdf\n")
    client.send_chars("exit\n")
    client.send_chars("exit\n")
    client.wait_until_tty_matches(1, "Connection to 192.168.2.2 closed.")
    client.screenshot("prompt03")

    # Wait for the auditbeat flush interval
    time.sleep(2)
    print(server.execute("cat /var/lib/auditbeat/auditbeat")[1])

    with subtest("Auditbeat log should have keystrokes entries for tty input"):
        keystrokes = beatgrep(
            lambda obj: obj["auditd"]["summary"]["object"]["type"] == "keystrokes")
        keystrokes = [
            k['auditd']['summary']['object']['primary'] for k in keystrokes]
        assert keystrokes == ['rm /tmp/asdf\rexit\r', 'ps auxf\rsudo -i\rexit\r'
                            ], f"Keystrokes did not match. Got: {keystrokes!r}"

    with subtest("Auditbeat log should have one entry for the rm command"):
        rm = beatgrep(lambda obj: obj['auditd']['summary']['object']['primary'] ==
                    '/run/current-system/sw/bin/rm')
        assert len(rm) == 1
        rm = rm[0]
        import pprint
        pprint.pprint(rm)

        assert rm['auditd']['summary']['actor']['primary'] == 'customer'
        assert rm['auditd']['summary']['actor']['secondary'] == 'root'
        assert rm['process']['working_directory'] == '/root'
        assert rm['process']['args'] == ['rm', '/tmp/asdf']


    with subtest("Graylog should have received a connection from auditbeat"):
        graylog = server.execute("journalctl -q -o cat -u netcatgraylog --grep 'Connection received'")[1]
        print(graylog)
        assert 'Connection received on localhost' in graylog
