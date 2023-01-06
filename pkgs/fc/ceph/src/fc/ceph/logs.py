"""Slow requests histogram tool.

Reads a ceph.log file and filters by lines matching a given RE (default:
slow request). For all filtered lines that contain an OSD identifier,
the OSD identifier is counted. Prints a top-N list of OSDs having slow
requests. Useful for identifying slacky OSDs.
"""

import argparse
import collections
import gzip
import re

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
        for (i, osd) in sorted(hist, reverse=True):
            hist_bar = "*" * int(35 * i / max_incidents)
            print(f"{osd:>15} - {i:>7} - {hist_bar}")
            if n >= first_n:
                break
            n += 1
