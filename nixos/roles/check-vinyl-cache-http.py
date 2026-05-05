import subprocess
import sys

ports = []

for line in (
    subprocess.check_output(["varnishadm", "debug.listen_address"])
    .decode("ascii")
    .splitlines()
):
    line = line.strip()
    if not line:
        continue
    _, ip, port = line.split()
    ports.append((ip, port))

if not ports:
    print("No listen_address reported by varnishadm")
    sys.exit(2)

STATUS = 0

for ip, port in ports:
    if ":" in ip:
        ip_version = "-6"
        print(f"Checking [{ip}]:{port} ...")
    else:
        ip_version = "-4"
        print(f"Checking {ip}:{port} ...")
    proc = subprocess.run(
        [
            "check_http", "-H", ip, "-p", port, ip_version,
            "-c", "10", "-w", "3", "-t", "20",
            "-e", "HTTP",
        ]
    )  # fmt: skip
    print()
    STATUS = max([STATUS, proc.returncode])

sys.exit(STATUS)
