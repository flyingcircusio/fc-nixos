import os
import subprocess


def get_vcs_date():
    """
    Tries to get the last commit date from the VCS.
    Priority: Mercurial (hg) -> Git -> fallback 'unknown'.
    """
    # 1. Try Mercurial (The preferred way)
    try:
        # 'hg log -r . -d' gives the date of the current revision
        # Format: 2026-08-05 14:30:00
        date_str = (
            subprocess.check_output(
                'hg log -r . --template "{date|short}"',
                shell=True,
                stderr=subprocess.DEVNULL,
            )
            .decode()
            .strip()
        )
        if date_str:
            # Handle cases where hg might return a timestamp instead of a formatted date
            if "." in date_str and date_str.replace(".", "").isdigit():
                import datetime

                return datetime.datetime.fromtimestamp(float(date_str)).strftime(
                    "%Y-%m-%d"
                )
            return date_str[:10]  # Ensure YYYY-MM-DD

    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    # 2. Try Git (The fallback)
    try:
        date_str = (
            subprocess.check_output(
                "git show --format=format:%cI", shell=True, stderr=subprocess.DEVNULL
            )
            .decode()
            .splitlines()[0]
            .strip()
        )
        if date_str:
            return date_str[:10]  # Return YYYY-MM-DD from ISO string
    except (subprocess.CalledProcessError, IndexError, FileNotFoundError):
        pass

    return "unknown"


def define_env(env):
    # Priorität 1: Explizite Version über Environment-Variable
    v = os.environ.get("version", "0.0000000")

    # Priorität 2: VCS-Datum, falls keine gültige Version gesetzt ist
    if v == "0.0000000":
        v = get_vcs_date()

    env.variables["version"] = v
    env.variables["release"] = v
