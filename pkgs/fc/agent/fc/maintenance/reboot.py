import subprocess
import time


def reboot(coldboot=False):
    print(
        "shutdown at {}".format(
            time.strftime(
                "%Y-%m-%d %H:%M:%S UTC", time.gmtime(time.time() + 60)
            )
        )
    )
    if coldboot:
        subprocess.check_call(["poweroff"])
    else:
        subprocess.check_call(["reboot"])
