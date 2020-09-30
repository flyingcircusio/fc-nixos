#!/usr/bin/env python3
# Simplified version of https://raw.githubusercontent.com/mzupan/nagios-plugin-mongodb/master/check_mongodb.py

import optparse
import sys
import numbers
import traceback
import time

import pymongo


def numeric_type(param):
    return param is None or isinstance(param, numbers.Real)


def check_levels(param, warning, critical, message, ok=[]):
    if numeric_type(critical) and numeric_type(warning):
        if param >= critical:
            print("CRITICAL - " + message)
            return 2
        elif param >= warning:
            print("WARNING - " + message)
            return 1
        else:
            print("OK - " + message)
            return 0
    else:
        if param in critical:
            print("CRITICAL - " + message)
            return 2

        if param in warning:
            print("WARNING - " + message)
            return 1

        if param in ok:
            print("OK - " + message)
            return 0

        # unexpected param value
        print(f"CRITICAL - Unexpected value: {param}; {message}")
        return 2


def check_connect(conn_time):
    warning = 3
    critical = 6
    message = "Connection took %.3f seconds" % conn_time
    return check_levels(conn_time, warning, critical, message)


def check_feature_compat_version(con):

    major_version = ".".join(str(x) for x in con.server_info()["versionArray"][:2])

    if major_version == "3.2":
        print("WARNING - MongoDB version 3.2 is outdated")
        return 1

    try:
        res = con.admin.command({"getParameter": 1, "featureCompatibilityVersion": 1})
    except pymongo.errors.PyMongoError as e:
        print("CRITICAL - MongoDB error:", e)
        return 2

    if major_version == "3.4":
        compat_version = res["featureCompatibilityVersion"]
    else:
        compat_version = res["featureCompatibilityVersion"]["version"]

    if compat_version < major_version:
        print(
            f"WARNING - feature compatibility version is {compat_version}, running MongoDB is {major_version}."
            + " Set feature compatibility version to running version before upgrading."
        )
        return 1
    else:
        print(
            f"OK - feature compatibility version matches running MongoDB {major_version}"
        )
        return 0


def _main():
    p = optparse.OptionParser(
        conflict_handler="resolve",
        description="This Nagios plugin checks the health of mongodb.",
    )

    p.add_option(
        "-A",
        "--action",
        action="store",
        type="choice",
        dest="action",
        default="connect",
        help="The action you want to take",
        choices=["connect", "feature_compat_version"],
    )
    p.add_option(
        "-d",
        "--database",
        action="store",
        dest="database",
        default="admin",
        help="Specify the database to check",
    )

    options, _ = p.parse_args()
    action = options.action

    start = time.time()

    con = pymongo.MongoClient()

    try:
        # Ping to check that the server is responding.
        con.admin.command("ping")
    except pymongo.errors.PyMongoError as e:
        print("CRITICAL - MongoDB error:", e)
        return 2

    conn_time = time.time() - start

    if action == "feature_compat_version":
        return check_feature_compat_version(con)
    else:
        return check_connect(conn_time)


def main():
    try:
        return _main()
    except Exception:
        traceback.print_exc()
        return 3


if __name__ == "__main__":
    sys.exit(main())
