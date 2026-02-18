import json
import re
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Generator

import IPy
from fc.ceph.util import run


@dataclass
class OpsLogState:
    last_processed_datetime: datetime
    last_gced_day: date

    @classmethod
    def read_from(cls, file: Path):
        with file.open("r") as f:
            json_data = json.loads(f.read())
            return OpsLogState(
                last_gced_day=date.fromisoformat(json_data["last_gced_day"]),
                last_processed_datetime=datetime.strptime(
                    json_data["last_processed_datetime"], "%Y-%m-%dT%H"
                ),
            )

    def write_to(self, file: Path):
        with file.open("w") as f:
            f.write(
                json.dumps(
                    dict(
                        last_gced_day=self.last_gced_day.strftime("%Y-%m-%d"),
                        last_processed_datetime=self.last_processed_datetime.strftime(
                            "%Y-%m-%dT%H"
                        ),
                    )
                )
            )


class OpsLog:
    def __init__(self, state_file: Path, internal_networks: list[IPy.IP]):
        self.state_file = state_file
        self.internal_networks = internal_networks
        self.opslog_ptrn = re.compile(
            r"^[\d]{4}-[\d]{2}-[\d]{2}-[\d]{2}-[A-Za-z0-9.-]+$"
        )
        self._local_ips = {}

        if not self.state_file.exists():
            self.opslog_state = OpsLogState(
                datetime.today() - timedelta(days=1),
                date.today() - timedelta(days=2),
            )
            self.opslog_state.write_to(self.state_file)
        else:
            self.opslog_state = OpsLogState.read_from(self.state_file)

    @contextmanager
    def get_pending_stats_by_day(
        self,
    ) -> Generator[dict[date, list[str]], None, None]:
        """
        Provide pending log objects from the timespan between the last processed hour and
        now. The current hour is left out because this is only running once a day once all stats
        were collected.

        It's crucial to commit the processed data within the context manager: if an
        exception is thrown, the processed days won't be saved for a retry.
        """

        # Logs are recorded by hour
        max_date = datetime.now().replace(microsecond=0, second=0, minute=0)
        start = self.opslog_state.last_processed_datetime + timedelta(hours=1)

        stats_by_day: dict[date, list[str]] = {}

        start_day = start.date()
        end_day = max_date.date()

        day = start_day
        while day <= end_day:
            logs_by_hour: list[list[str]] = [[] for _ in range(0, 24)]
            for entry in run.json.radosgw_admin(
                "log", "list", f"--date={day.strftime('%Y-%m-%d')}"
            ):
                if self.opslog_ptrn.match(entry):
                    logs_by_hour[int(entry[11:13])].append(entry)

            if day == end_day:
                logs_by_hour = logs_by_hour[: max_date.hour]
            if day == start_day:
                logs_by_hour = logs_by_hour[start.hour :]

            log_list = [obj for hour in logs_by_hour for obj in hour]

            if log_list:
                try:
                    stats_by_day[day].extend(log_list)
                except KeyError:
                    stats_by_day[day] = log_list

            day += timedelta(days=1)

        self.opslog_state.last_processed_datetime = max_date - timedelta(
            hours=1
        )

        yield stats_by_day

        self.opslog_state.write_to(self.state_file)

    def gc_log_objects(self):
        last_date = self.opslog_state.last_processed_datetime.date()
        assert date.today() >= last_date, (
            f"last_processed_datetime ({self.opslog_state.last_processed_datetime} must not be in the future)"
        )

        day = self.opslog_state.last_gced_day + timedelta(days=1)
        end = last_date - timedelta(days=1)

        while day < end:
            for obj in run.json.radosgw_admin(
                "log", "list", f"--date={day.strftime('%Y-%m-%d')}"
            ):
                run.radosgw_admin("log", "rm", f"--object={obj}")

            self.opslog_state.last_gced_day = day
            self.opslog_state.write_to(self.state_file)

            day += timedelta(days=1)

    def get_object(self, name: str):
        result = run.json.radosgw_admin("log", "show", f"--object={name}")

        # We filter out internal traffic, so the log_sum is wrong. Hence, delete it to
        # not use it by accident further down.
        del result["log_sum"]

        result["log_entries"] = [
            entry
            for entry in result["log_entries"]
            if not self._is_local_ip(self._ip_from_log_entry(entry))
        ]

        return result

    def _is_local_ip(self, ip: IPy.IP) -> bool:
        if ip not in self._local_ips:
            self._local_ips[ip] = False
            for net in self.internal_networks:
                if ip in net:
                    self._local_ips[ip] = True
                    break
        return self._local_ips[ip]

    def _ip_from_log_entry(self, log_entry) -> IPy.IP:
        # The list is of the format
        #
        # [
        #  { "HTTP_X_HEADER": "value" },
        #  { "HTTP_X_OTHER": "othervalue" }
        # ]
        for header in log_entry.get("http_x_headers", []):
            name = next(iter(header.keys()), None)
            if name == "HTTP_X_REAL_IP":
                return IPy.IP(header[name])
        return IPy.IP(log_entry["remote_addr"])
