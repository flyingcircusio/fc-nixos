import datetime
import os
import pwd
import subprocess
import sys


def main():
    exclude_file = sys.argv[1]
    log_file = sys.argv[2]
    rc = []
    users_to_scan = [
        user
        for user in pwd.getpwall()
        if user.pw_uid >= 1000 and user.pw_dir != "/var/empty"
    ]
    print(f"Running fc-userscan for {len(users_to_scan)} users")
    for user in users_to_scan:
        print(f"Scanning {user.pw_dir} as {user.pw_name}")
        p = subprocess.Popen(
            [
                "fc-userscan",
                "-r",
                "-c",
                user.pw_dir + "/.cache/fc-userscan.cache",
                "-L10000000",
                "--unzip=*.egg",
                "-E",
                exclude_file,
                user.pw_dir,
            ],
            stdin=subprocess.DEVNULL,
            preexec_fn=lambda: os.setresuid(user.pw_uid, 0, 0),
        )
        rc.append(p.wait())

    status = max(rc)
    print("Overall status of fc-userscan calls:", status)

    if status >= 2:
        print("Aborting garbagecollect. See above for fc-userscan errors")
        sys.exit(2)
    if status >= 1:
        print("Aborting garbagecollect. See above for fc-userscan warnings")
        sys.exit(1)

    print("Running nix-collect-garbage")
    rc = subprocess.run(
        ["nix-collect-garbage", "--delete-older-than", "3d"],
        check=True,
        stdin=subprocess.DEVNULL,
    ).returncode

    if rc > 0:
        print(
            f"nix-collect-garbage failed with status {rc}. "
            "See above for command output."
        )
        sys.exit(3)

    open(log_file, "w").write(str(datetime.datetime.now()) + "\n")
    print("fc-collect-garbage finished without problems.")


if __name__ == "__main__":
    main()
