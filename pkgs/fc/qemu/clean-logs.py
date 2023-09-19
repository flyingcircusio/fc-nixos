"""
A helper to clean up log files from fc.qemu.

The logrotate targets aren't smart enough because we have VMs that move around
and thus would end up with missing files, but `missingok` doesn't help if the
pattern doesn't match any more.

In addition we may have files that have not been written to for a long time but
do correspond to a VM still running here.

So this script deletes log files, iff:

1. the file is not open, AND
2. it is older than 14 days.

"""
import datetime
import pathlib
import re
import subprocess
import time

MAX_AGE = datetime.timedelta(days=14)
VM_LOG_DIR = pathlib.Path("/var/log/vm")
VM_LOG_NAME_PATTERN = re.compile(r"[0-9a-zA-Z]+\.log")

# Find logs of running VMs

print("Checking open files ...")

lsof = subprocess.run(
    ["lsof", "-F", "n", "+D", VM_LOG_DIR], capture_output=True
)
# Expected output:
# $ lsof +D /var/log/vm -F n
# p23052
# n/var/log/vm/release2305dev01.log
# p319664
# n/var/log/vm/mailstubtest01.log
# p321165
# n/var/log/vm/services34.log
# p332886
# n/var/log/vm/services08.log
# p333454

open_files = set()

for open_file in lsof.stdout.decode("ascii").splitlines():
    prefix, path = open_file[0], open_file[1:]
    if prefix != "n":
        continue
    open_files.add(path)

print("Checking for files to unlink...")

mtime_cutoff = time.time() - MAX_AGE.total_seconds()
for logfile in VM_LOG_DIR.glob("*"):
    is_in_use = str(logfile) in open_files
    is_old = logfile.stat().st_mtime < mtime_cutoff
    is_empty = not logfile.stat().st_size
    if is_in_use:
        continue
    if is_old or is_empty:
        print(logfile.name, logfile.stat().st_size, logfile.stat().st_mtime)
        logfile.unlink(missing_ok=True)

# Clean up all old fc.qemu rotated logs (14 days is sufficient)
