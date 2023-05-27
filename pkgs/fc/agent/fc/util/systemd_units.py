from typing import Optional

import pendulum
import pystemd.systemd1
from fc.util.checks import CheckResult


def from_nano_timestamp(timestamp) -> Optional[pendulum.DateTime]:
    """
    Converts systemd's timestamps in nanoseconds into a DateTime object
    using local timezone.
    """
    if timestamp:
        return pendulum.from_timestamp(timestamp / 1_000_000, "local")


def check_status(
    log,
    unit_name,
    critical_states,
    warning_states,
) -> CheckResult:
    unit = pystemd.systemd1.Unit(unit_name)

    try:
        unit.load()
    except pystemd.dbusexc.DBusInvalidArgsError:
        raise

    # LoadError is a 2-tuple with two empty strings if loading succeeded.
    if unit.Unit.LoadError[0]:
        error, msg = [b.decode("utf8") for b in unit.Unit.LoadError]
        return CheckResult(errors=[f"{error}: {msg}"])

    active_state = unit.Unit.ActiveState.decode()
    state_change_dt = from_nano_timestamp(unit.Unit.StateChangeTimestamp)

    errors = []
    warnings = []
    ok_info = []

    headline = f"{unit_name} in state {active_state}"

    if state_change_dt:
        abs_time = state_change_dt.to_rfc822_string()
        rel_time = state_change_dt.diff_for_humans()
        headline += f" since {abs_time}; {rel_time}."
    else:
        headline += "."

    if active_state in critical_states:
        errors.append(headline)
    elif active_state in warning_states:
        warnings.append(headline)
    else:
        ok_info.append(headline)

    match active_state:
        case "failed":
            if unit.Service.ExecMainPID and unit.Service.ExecMainStatus:
                errors.append(
                    f"Main process exited, status {unit.Service.ExecMainStatus}"
                )

            invocation_id = bytes(unit.Unit.InvocationID).hex()
            errors.append(
                f"journalctl _SYSTEMD_INVOCATION_ID={invocation_id} shows "
                "log output of the last run."
            )

    return CheckResult(errors=errors, warnings=warnings, ok_info=ok_info)


def check_find_failed(
    log,
    exclude,
    critical,
) -> CheckResult:
    if exclude is None:
        exclude = set()
    else:
        exclude = set(exclude)

    out = []

    manager = pystemd.systemd1.Manager()
    manager.load()
    failed_units = [
        t[0].decode("utf8")
        for t in manager.Manager.ListUnitsFiltered(["failed"])
    ]

    relevant_failed_units = [u for u in failed_units if u not in exclude]

    if failed_units:
        out.append(f"Failed units ({len(relevant_failed_units)}):")

        for unit in relevant_failed_units:
            out.append(unit)

    if critical and out:
        return CheckResult(errors=out)
    elif out:
        return CheckResult(warnings=out)

    return CheckResult(ok_info=["No failed units."])
