import argparse
import logging
import re
import subprocess

import nagiosplugin


class Interfaces(nagiosplugin.Resource):
    def __init__(self, interfaces, auto_detect, exclude):
        #: {iface_name: context_name or 'auto', ...}
        self.ifaces = {iface: iface for iface in interfaces}
        self.auto_detect = auto_detect
        self.exclude = exclude

    def autodetect(self):
        """Generator for running network interfaces."""
        cmdline = ["ip", "-o", "link", "show"]
        logging.info("querying interfaces with %s", " ".join(cmdline))
        out = subprocess.check_output(cmdline).decode()
        logging.debug("%s", out)
        for line in out.split("\n"):
            # only act on eth devices
            if not re.match(r"\d+:\s+eth\w+", line):
                continue
            m = re.search(r"\d+:\s+([^:@ ]+@)??([^:@ ]+):\s<(.*)>", line)
            if m:
                ifname = m.group(2)
                flags = m.group(3).split(",")
                if ifname.startswith("eth") and "UP" in flags:
                    yield ifname

    def exists(self, iface):
        with open("/proc/net/dev") as dev:
            for line in dev:
                if "%s: " % iface in line:
                    return True
        logging.debug("%s no found in /proc/net/dev, skipping" % iface)
        return False

    def query(self, iface):
        cmdline = ["sudo", "ethtool", iface]
        logging.info('running "%s"' % " ".join(cmdline))
        stdout = subprocess.check_output(cmdline).decode()
        logging.debug(stdout)
        m = re.search(r"Link detected:\s*(.*)$", stdout)
        if m and m.group(1) == "yes":
            m = re.search(r"Speed:\s*([0-9]+)", stdout)
            if m:
                speed = int(m.group(1))
            else:
                raise RuntimeError(
                    "cannot parse ethtool output for speed:\n" + stdout
                )
        else:
            speed = 0

        m = re.search(r"Duplex:\s*(\w+)", stdout)
        if m:
            duplex = m.group(1).lower()
        else:
            raise RuntimeError(
                "cannot parse ethtool output for duplex:\n" + stdout
            )

        logging.debug("%s: (%i, %s)" % (iface, speed, duplex))
        return (speed, duplex)

    def setup_interfaces(self):
        if self.auto_detect:
            for iface in self.autodetect():
                if iface in self.exclude:
                    logging.info("%s is excluded" % iface)
                else:
                    self.ifaces.setdefault(iface, "auto")
        if not self.ifaces:
            raise nagiosplugin.CheckError("no interfaces specified")
        logging.info("interfaces=%r", self.ifaces)

    def probe(self):
        self.setup_interfaces()
        for iface, context in self.ifaces.items():
            if not self.exists(iface):
                continue
            speed, duplex = self.query(iface)
            yield nagiosplugin.Metric(
                "{}_spd".format(iface),
                speed,
                "Mb/s",
                min=0,
                context="{}_spd".format(context),
            )
            yield nagiosplugin.Metric(
                "{}_dup".format(iface),
                duplex,
                context="{}_dup".format(context),
            )


class DuplexContext(nagiosplugin.Context):
    def __init__(self, name, duplex):
        super(DuplexContext, self).__init__(name, fmt_metric="{value} duplex")
        self.duplex = duplex.lower()

    def evaluate(self, metric, resource):
        if metric.value.lower() != self.duplex:
            return self.result_cls(
                nagiosplugin.Critical,
                "{} {} (!= {})".format(metric.name, metric.value, self.duplex),
                metric,
            )
        else:
            return self.result_cls(nagiosplugin.Ok, None, metric)


def create_contexts(interfaces, defspeed, defduplex):
    yield nagiosplugin.ScalarContext("auto_spd", "", defspeed)
    yield DuplexContext("auto_dup", defduplex)
    for iface in interfaces:
        name, speed, duplex = (iface + ",,").split(",")[0:3]
        yield nagiosplugin.ScalarContext(
            "{}_spd".format(name), "", speed or defspeed
        )
        yield DuplexContext("{}_dup".format(name), duplex or defduplex)


class InterfacesSummary(nagiosplugin.Summary):
    def ok(self, results):
        return ", ".join(
            str(r) for r in results if r.metric.name.endswith("_spd")
        )


@nagiosplugin.guarded
def main():
    argp = argparse.ArgumentParser(
        description="check speed and duplex mode of network interfaces"
    )
    argp.add_argument(
        "-i",
        "--interface",
        dest="interfaces",
        metavar="IFACE[,SPEED[,DUPLEX]]",
        action="append",
        help="probe named interface (if no speed and duplex "
        "mode are stated, check for default values)",
        default=[],
    )
    argp.add_argument(
        "-a",
        "--auto-detect",
        action="store_true",
        default=False,
        help="auto-detect all active interfaces",
    )
    argp.add_argument(
        "-x",
        "--exclude",
        action="append",
        default=[],
        metavar="IFACE",
        help="exclude interface from auto detection",
    )
    argp.add_argument(
        "-s",
        "--speed",
        default="1000:1000",
        help="require at least SPEED Mb/s (default: " "%(default)s)",
    )
    argp.add_argument(
        "-d",
        "--duplex",
        default="full",
        help="require duplex mode (default: %(default)s)",
    )
    argp.add_argument(
        "-v",
        "--verbose",
        default=0,
        action="count",
        help="increase output verbosity (use up to 3 times)",
    )
    argp.add_argument(
        "-t",
        "--timeout",
        default=10,
        help="abort execution after TIMEOUT seconds",
    )
    args = argp.parse_args()
    check = nagiosplugin.Check(
        Interfaces(
            [i.split(",")[0] for i in args.interfaces],
            args.auto_detect,
            args.exclude,
        ),
        InterfacesSummary(),
    )
    for ctx in create_contexts(args.interfaces, args.speed, args.duplex):
        check.add(ctx)
    check.main(args.verbose, args.timeout)


if __name__ == "__main__":
    main()
