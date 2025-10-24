import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from check_tls_cert import Severity, check_certificate


def create_test_certificate(cert_path, days_valid=30, start_date=None) -> None:
    """Creates a certificate using the openssl command."""
    if start_date is None:
        start_date = datetime.now(timezone.utc)

    end_date = start_date + timedelta(days=days_valid)

    cmd = [
        "openssl",
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-keyout",
        cert_path.with_suffix(".key"),
        "-out",
        cert_path,
        "-nodes",
        "-subj",
        "/CN=test.example.com",
        "-set_serial",
        "1",
        "-not_before",
        start_date.strftime("%Y%m%d%H%M%SZ"),
        "-not_after",
        end_date.strftime("%Y%m%d%H%M%SZ"),
    ]

    subprocess.run(cmd, check=True, capture_output=True)


@pytest.fixture
def cert_path(tmp_path) -> Path:
    cert_path = tmp_path / "test.crt"
    create_test_certificate(cert_path)
    return cert_path


def test_valid_certificate(cert_path):
    result = check_certificate(cert_path, "test.example.com")

    assert result.severity == Severity.OK
    assert not result.errors
    assert not result.warnings
    assert result.ok_info == [
        "Certificate for test.example.com is valid for more than 25 days."
    ]


def test_warn_days_threshold(cert_path):
    result = check_certificate(cert_path, "test.example.com", warn_days=31)
    assert result.severity == Severity.WARNING
    assert result.warnings == [
        "Certificate for test.example.com expires within warning time (31 days)."
    ]


def test_crit_days_threshold(cert_path):
    result = check_certificate(
        cert_path, "test.example.com", warn_days=31, crit_days=30
    )
    assert result.severity == Severity.CRITICAL
    assert result.errors == [
        "Certificate for test.example.com expires within critical time (30 days)."
    ]


def test_critical_for_expired_cert(tmp_path):
    cert_path = tmp_path / "expired.crt"
    # Create certificate that expired yesterday
    past_date = datetime.now(timezone.utc) - timedelta(days=2)
    create_test_certificate(cert_path, days_valid=1, start_date=past_date)

    result = check_certificate(cert_path, "test.example.com")

    assert result.severity == Severity.CRITICAL
    assert result.errors == ["Certificate for test.example.com has expired."]


def test_critical_when_path_is_missing():
    result = check_certificate(Path("/nonexistent/cert.crt"))

    assert result.severity == Severity.CRITICAL
    assert "file not found" in result.errors[0]


def test_critical_when_path_is_a_dir(tmp_path):
    result = check_certificate(tmp_path)

    assert result.severity == Severity.CRITICAL
    assert "path is not a file" in result.errors[0]


def test_cli_integration(cert_path):
    """Test that calling the script works for the happy path."""
    result = subprocess.run(
        [
            sys.executable,
            str(Path(__file__).parent / "check_tls_cert.py"),
            str(cert_path),
        ],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0
    assert "OK:" in result.stdout
    assert "notAfter" in result.stdout
    assert not result.stderr
