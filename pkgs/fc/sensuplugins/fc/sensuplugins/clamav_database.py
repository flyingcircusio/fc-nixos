import sys
from pathlib import Path
from subprocess import run


def main():
    database_dir = Path("/var/lib/clamav")
    cld_daily = database_dir / "daily.cld"
    cvd_daily = database_dir / "daily.cvd"

    warnings = []
    errors = []
    other_output = []

    if not cld_daily.exists() and not cvd_daily.exists():
        print("clamav database CRITICAL: daily.c?d file missing!")
        sys.exit(2)

    if cld_daily.exists() and cvd_daily.exists():
        warnings.append(
            "clamav database WARNING: both daily.cld and daily.cvd exist. "
            "This is unexpected for normal operations, please check."
        )

    check_age_cmd = [
        "check_file_age",
        "-w",
        "86400",
        "-c",
        "172800",
    ]

    max_returncode = 0

    if cld_daily.exists():
        proc = run(check_age_cmd + [cld_daily], capture_output=True, text=True)

        max_returncode = max(max_returncode, proc.returncode)
        out = proc.stdout.strip()

        if proc.returncode == 2:
            errors.append(out)
        elif proc.returncode == 1:
            warnings.append(out)
        else:
            other_output.append(out)

    if cvd_daily.exists():
        proc = run(check_age_cmd + [cvd_daily], capture_output=True, text=True)

        max_returncode = max(max_returncode, proc.returncode)
        out = proc.stdout.strip()

        if proc.returncode == 2:
            errors.append(out)
        elif proc.returncode == 1:
            warnings.append(out)
        else:
            other_output.append(out)

    if errors:
        print(" | ".join(errors + warnings))
        sys.exit(2)

    if warnings:
        print(" | ".join(warnings))
        sys.exit(1)

    # Can be:
    # * Normal (0, OK) exit when only one of the files exists and is recent.
    # * At least one unexpected error code > 2 when checking the files.
    print(" | ".join(other_output))
    sys.exit(max_returncode)


if __name__ == "__main__":
    main()
