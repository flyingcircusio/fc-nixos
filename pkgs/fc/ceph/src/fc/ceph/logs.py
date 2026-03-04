"""Slow requests histogram tool.

Reads a ceph.log file and filters by lines matching a given RE (default:
slow request). For all filtered lines that contain an OSD identifier,
the OSD identifier is counted. Prints a top-N list of OSDs having slow
requests. Useful for identifying slacky OSDs.
"""

import collections
import gzip
import json
import re
from pathlib import Path

import IPy
from fc.ceph.util import directory
from fc.ceph.util.opslog import OpsLog

R_OSD = re.compile(r"osd\.[0-9]+")


def read(logfile, include, exclude):
    i_filter = re.compile(include) if include else None
    e_filter = re.compile(exclude) if exclude else None
    if logfile.endswith(".gz"):
        f = gzip.open(logfile, mode="rb")
    else:
        f = open(logfile, mode="rb")
    osds = []
    for line in f:
        line = line.decode().strip()
        if i_filter and not i_filter.search(line):
            continue
        if e_filter and e_filter.search(line):
            continue
        m = R_OSD.search(line)
        if m:
            osds.append(m.group(0))
    f.close()
    return osds


class LogTasks(object):
    def slowreq_histogram(self, include, exclude, first_n, filenames):
        incidents = collections.defaultdict(int)
        for f in filenames:
            osds = read(f, include, exclude)
            for o in osds:
                incidents[o] += 1
        hist = [(i, o) for o, i in incidents.items()]
        max_incidents = max([x[0] for x in hist], default=0)
        n = 1
        for i, osd in sorted(hist, reverse=True):
            hist_bar = "*" * int(35 * i / max_incidents)
            print(f"{osd:>15} - {i:>7} - {hist_bar}")
            if n >= first_n:
                break
            n += 1

    def account_s3_traffic(self, state_file: Path, enc_file: Path):
        final_stats = []
        with directory.directory_connection(enc_file, ring="max") as d:
            with open(enc_file) as f:
                enc = json.load(f)
                location = enc["parameters"]["location"]
            internal_networks = []
            for vlan, nets in d.lookup_networks(location).items():
                for network in nets:
                    internal_networks.append(IPy.IP(network))

            ops_log = OpsLog(state_file, internal_networks)

            with ops_log.get_pending_stats_by_day() as logs:
                for day, objs in logs.items():
                    traffic_by_owner = {}
                    for obj in objs:
                        usage_log = ops_log.get_object(obj)
                        if not usage_log.get("bucket_owner"):
                            continue

                        stats = traffic_by_owner.setdefault(
                            usage_log["bucket_owner"], [0, 0]
                        )
                        for entry in usage_log["log_entries"]:
                            stats[0] += entry["bytes_sent"]
                            stats[1] += entry["bytes_received"]

                    for user, (sent, recv) in traffic_by_owner.items():
                        final_stats.append(
                            [
                                day.strftime("%Y-%m-%d"),
                                str(recv),
                                str(sent),
                                user,
                            ]
                        )

                # persist data (atomic)
                print(f"Gathered {len(final_stats)} samples to account")
                d.store_s3_traffic(final_stats)

    def gc_s3_traffic(self, state_file: Path):
        OpsLog(state_file).gc_log_objects()
