# Common code for Nagios-style checks.
from typing import Optional
from dataclasses import dataclass, field


@dataclass
class CheckResult:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    ok_info: list[str] = field(default_factory=list)

    def format_output(self) -> str:
        if self.errors:
            return "CRITICAL: " + " ".join(self.errors + self.warnings)

        if self.warnings:
            return "WARNING: " + " ".join(self.warnings)

        if self.ok_info:
            return "OK: " + " ".join(self.ok_info)

        return "OK"

    @property
    def exit_code(self) -> int:
        if self.errors:
            return 2

        if self.warnings:
            return 1

        return 0

    @staticmethod
    def merge(first, second):
        return CheckResult(
            first.errors + second.errors,
            first.warnings + second.warnings,
            first.ok_info + second.ok_info,
        )
