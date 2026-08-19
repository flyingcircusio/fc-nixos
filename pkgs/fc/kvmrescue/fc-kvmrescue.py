#!/usr/bin/env nix-shell
#! nix-shell -p uv -i "uv run --script"
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["rich"]
# ///

import sys

import rich


def main(kvmhostname: str):
    rich.print("Ohai")


# - zu Beginn: hostname des toten hosts angeben
# - host via directory API out of service setzen
# - tote VMs anhand von Ceph Lock identifizieren:
# - zuerst oneshot fc-ipmitool `power status`: wenn host klar down ist, dann können alle rbd locks aufgeräumt werden
# - falls nicht:
# - BMC nicht erreichbar: TBD
# - interaktives Anzeigen der SOL


if __name__ == "__main__":
    main(sys.argv[0])
