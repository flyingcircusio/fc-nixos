#!/usr/bin/env python3
"""HTTP status check.

Check the status code from an HTTP request, with options for following
redirects or not.
"""

import argparse
import os
import sys
import urllib.parse

import requests
from requests_toolbelt.adapters.source import SourceAddressAdapter


def err(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def unknown(msg):
    print(f"HTTP UNKNOWN - {msg}")
    sys.exit(3)


def warning(msg):
    print(f"HTTP WARNING - {msg}")
    sys.exit(1)


def critical(msg):
    print(f"HTTP CRITICAL - {msg}")
    sys.exit(2)


def ok(msg):
    print(f"HTTP OK - {msg}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-4", "--ipv4", action="store_true", help="Only use IPv4"
    )
    parser.add_argument(
        "-6", "--ipv6", action="store_true", help="Only use IPv6"
    )
    parser.add_argument(
        "-e",
        "--expect",
        type=int,
        action="append",
        help="Expected status codes",
    )
    parser.add_argument(
        "-f", "--follow", action="store_true", help="Follow HTTP redirects"
    )
    parser.add_argument("URL", help="URL to be fetched")

    args = parser.parse_args()

    # forcing a specific address family by binding to its wildcard
    # address works on linux, but does not seem to work on darwin.
    source_address = None
    if args.ipv4 and args.ipv6:
        err("conflicting arguments, -4 and -6 cannot be specified together")
    elif args.ipv4:
        source_address = "0.0.0.0"
    elif args.ipv6:
        source_address = "::"

    if args.expect is not None and any(
        map(lambda n: n < 100 or n > 599, args.expect)
    ):
        err("invalid expected status code")

    try:
        url = urllib.parse.urlsplit(args.URL)
    except ValueError as ex:
        err(f"could not parse URL: {ex}")

    if url.scheme != "http" and url.scheme != "https":
        err(f"unsupported url scheme: {url.scheme}")

    if url.hostname is None:
        err("empty hostname in URL")

    session = requests.Session()
    # default redirect depth limit is 10, which matches
    # monitoring-plugins -- chrome and firefox have default limits of
    # 20. the browsers also perform redirection loop detection,
    # however we don't implement this yet.
    session.max_redirects = 10

    if url.username is not None:
        session.auth = (url.username, url.password)

    target = urllib.parse.urlunsplit(
        (url.scheme, url.hostname, url.path, url.query, "")
    )

    if source_address is not None:
        session.mount("http://", SourceAddressAdapter(source_address))
        session.mount("https://", SourceAddressAdapter(source_address))

    try:
        resp = session.get(target, allow_redirects=args.follow, timeout=10)
    except requests.ConnectionError as ex:
        critical(f"could not connect to remote host: {ex}")
    except requests.TooManyRedirects as ex:
        warning("maximum redirection depth exceeded")
    except requests.Timeout as ex:
        critical("request to remote host exceeded timeout: 10s")

    if args.expect is None:
        if resp.status_code >= 500:
            critical(
                f"request returned server error status code: {resp.status_code}"
            )
        elif resp.status_code >= 400:
            warning(
                f"request returned client error status code: {resp.status_code}"
            )
    elif resp.status_code not in args.expect:
        critical(
            f"request returned unexpected status code: {resp.status_code}"
        )

    ok(f"request returned status code: {resp.status_code}")


if __name__ == "__main__":
    main()
