{ pkgs ? import <nixpkgs> {} , ... }:
pkgs.writeScript "check-xfs-broken.sh" ''
  # script to check if xfs is broken
  # does so by checking if '"echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.'
  # is in `dmesg`

  # if it is, then output the lines of dmesg that contain this message, and exit with a exit code of 2

  ${pkgs.util-linux}/bin/dmesg | grep -q 'xfs_log_commit_cil'
  # quiet grep
  if [ $? -eq 0 ]; then
    echo "CRITICAL - xfs is broken, offending lines:"
    ${pkgs.util-linux}/bin/dmesg | grep -C 20 'xfs_log_commit_cil'
    exit 2
  fi
  echo "OK - xfs is not broken"
''
