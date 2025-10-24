#!/usr/bin/env python3
"""TLS certificate file checker.

Checks for certs that are:
- expiring soon (with configurable warning and critical days thresholds)
- expired
"""

import argparse
import subprocess
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

SECONDS_PER_DAY = 86400


class Severity(Enum):
    """Severity levels for certificate check results."""

    OK = 0
    WARNING = 1
    CRITICAL = 2


@dataclass
class CertificateCheckResult:
    """Result of certificate validation with automatic severity calculation."""

    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    ok_info: list[str] = field(default_factory=list)

    def format_output(self) -> str:
        if self.errors:
            return "CRITICAL: " + "\n".join(self.errors + self.warnings)

        if self.warnings:
            return "WARNING: " + "\n".join(self.warnings)

        if self.ok_info:
            return "OK: " + "\n".join(self.ok_info)

        return "OK"

    @property
    def severity(self) -> Severity:
        """Calculate severity based on errors and warnings.

        Returns:
            Severity.CRITICAL if self.errors has items
            Severity.WARNING if self.warnings has items (and no errors)
            Severity.OK if both lists are empty
        """
        if self.errors:
            return Severity.CRITICAL
        elif self.warnings:
            return Severity.WARNING
        else:
            return Severity.OK


def run_openssl_x509_noout(
    cert_path: Path, *args
) -> subprocess.CompletedProcess:
    """Run OpenSSL x509 command with -noout and return the result.

    Args:
        cert_path: Path to certificate file
        args: x509 command args

    Returns:
        subprocess.CompletedProcess with stdout, stderr, and returncode
    """
    return subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", *args],
        capture_output=True,
        text=True,
    )


def check_certificate(
    cert_path: Path, hostname: str | None = None, crit_days=14, warn_days=25
) -> CertificateCheckResult:
    """Validate certificate using OpenSSL x509 -checkend command.

    Only checks if certificate is expired or will expire within critical time.
    """

    result = CertificateCheckResult()
    # Create hostname prefix for messages
    msg_prefix = f"Certificate for {hostname}" if hostname else "Certificate"

    # Check if certificate file exists and is readable
    if not cert_path.exists():
        result.errors.append(f"{msg_prefix} file not found: {cert_path}")
        return result

    if not cert_path.is_file():
        result.errors.append(f"{msg_prefix} path is not a file: {cert_path}")
        return result

    # We use -checkend three times, first to check if the cert IS already expired.
    proc = run_openssl_x509_noout(cert_path, "-checkend", "0")
    # OpenSSL 3.6.0 always returns 0 so we have to check the output, too.
    # https://github.com/openssl/openssl/issues/28928
    if proc.returncode == 1 or "Certificate will expire" in proc.stdout:
        result.errors.append(f"{msg_prefix} has expired.")
        return result

    # Second check: WILL the cert expire within <crit_days>?
    crit_sec = crit_days * SECONDS_PER_DAY
    proc = run_openssl_x509_noout(cert_path, "-checkend", str(crit_sec))
    if proc.returncode == 1 or "Certificate will expire" in proc.stdout:
        result.errors.append(
            f"{msg_prefix} expires within critical time ({crit_days} days)."
        )
        return result

    # Third check: WILL the cert expire within <warn_days>?
    warn_sec = warn_days * SECONDS_PER_DAY
    proc = run_openssl_x509_noout(cert_path, "-checkend", str(warn_sec))
    if proc.returncode == 1 or "Certificate will expire" in proc.stdout:
        result.warnings.append(
            f"{msg_prefix} expires within warning time ({warn_days} days)."
        )
        return result

    result.ok_info.append(
        f"{msg_prefix} is valid for more than {warn_days} days."
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="TLS certificate checker")
    parser.add_argument("cert_path", type=Path, help="Path to certificate file")
    parser.add_argument(
        "hostname", nargs="?", help="Hostname the certificate is used for"
    )
    parser.add_argument(
        "-w",
        "--warn",
        type=int,
        default=25,
        help="Warning threshold in days (default: 25)",
    )
    parser.add_argument(
        "-c",
        "--crit",
        type=int,
        default=14,
        help="Critical threshold in days (default: 14)",
    )

    args = parser.parse_args()

    # Validate thresholds
    if args.crit >= args.warn:
        parser.error("Critical threshold must be less than warning threshold!")

    result = check_certificate(
        args.cert_path, args.hostname, args.crit, args.warn
    )

    exit_code = result.severity.value
    output = result.format_output()
    # Add optional details, just the end date for now.
    try:
        end_date = run_openssl_x509_noout(
            args.cert_path, "-enddate"
        ).stdout.strip()
        output += f" ({end_date})"
    except Exception:  # noqa
        # It's ok, no need to crash the check for missing extra info.
        pass

    print(output)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
