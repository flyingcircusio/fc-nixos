import argparse
import socket
import sys
from pathlib import Path

import fc.ceph.keys
import fc.ceph.logs
import fc.ceph.maintenance
import fc.ceph.mgr
import fc.ceph.mon
import fc.ceph.osd
from fc.ceph import Environment

CONFIG_FILE_PATH = Path("/etc/ceph/fc-ceph.conf")


class SplitArgs(argparse.Action):
    # See https://stackoverflow.com/questions/52132076
    def __call__(self, parser, namespace, values, option_string=None):
        setattr(namespace, self.dest, values.split(","))


def main(args=sys.argv[1:]):
    hostname = socket.gethostname()

    parser = argparse.ArgumentParser()
    parser.set_defaults(subsystem=None, action=None)

    subparsers = parser.add_subparsers()

    # Note: subparser name bindings like `parser_create` are only ephemeral during construction
    # of individual subcommands and might be re-used for different command sections (mon, osd, ...)

    osd = subparsers.add_parser("osd", help="Manage OSDs.")
    osd.set_defaults(subsystem=fc.ceph.osd.OSDManager, action=osd.print_usage)
    osd_sub = osd.add_subparsers()

    parser_destroy = osd_sub.add_parser("destroy", help="Destroy an OSD.")
    parser_destroy.add_argument(
        "ids",
        help="IDs of OSD to destroy. Use `all` to destroy all local OSDs.",
    )
    parser_destroy.add_argument(
        "--force-objectstore-type",
        "-f",
        choices=fc.ceph.osd.OBJECTSTORE_TYPES,
        help="Use the destruction process for the specified objectstore type, "
        "instead of autodetecting it.",
    )
    parser_destroy.add_argument(
        "--unsafe-destroy",
        action="store_true",
        help="Skip the check whether an OSD is safe to destroy without "
        "affecting data redundancy. This can result in data loss or cluster failure!!",
    )
    parser_destroy.set_defaults(action="destroy")

    parser_create_fs = osd_sub.add_parser(
        "create-filestore", help="Create and activate a filestore OSD."
    )
    parser_create_fs.add_argument("device", help="Blockdevice to use")
    parser_create_fs.add_argument(
        "--journal",
        default="external",
        choices=["external", "internal"],
        help="Type of journal (on same disk or external)",
    )
    parser_create_fs.add_argument(
        "--journal-size",
        default=fc.ceph.osd.DEFAULT_JOURNAL_SIZE,
        help="Size of journal (LVM size units allowed).",
    )
    parser_create_fs.add_argument(
        "--crush-location", default=f"host={hostname}"
    )
    parser_create_fs.set_defaults(action="create_filestore")

    parser_create_bs = osd_sub.add_parser(
        "create-bluestore", help="Create and activate a bluestore OSD."
    )
    parser_create_bs.add_argument("device", help="Blockdevice to use")
    parser_create_bs.add_argument(
        "--wal",
        default="external",
        choices=["external", "internal"],
        help="Type of WAL (on same disk or external)",
    )
    parser_create_bs.add_argument(
        "--crush-location", default=f"host={hostname}"
    )
    parser_create_bs.set_defaults(action="create_bluestore")

    parser_activate = osd_sub.add_parser(
        "activate", help="Activate one or more OSDs."
    )
    parser_activate.add_argument(
        "ids",
        help="IDs of OSD to activate. Use `all` to activate all local OSDs.",
    )
    parser_activate.set_defaults(action="activate")

    parser_deactivate = osd_sub.add_parser(
        "deactivate", help="Deactivate an OSD."
    )
    parser_deactivate.add_argument(
        "ids",
        help="IDs of OSD to deactivate. "
        "Use `all` to deactivate all local OSDs.",
    )
    parser_deactivate.set_defaults(action="deactivate")

    parser_reactivate = osd_sub.add_parser(
        "reactivate", help="Reactivate an OSD."
    )
    parser_reactivate.add_argument(
        "ids",
        help="IDs of OSDs to reactivate (activate and deactivate). "
        "Use `all` to reactivate all local OSDs.",
    )
    parser_reactivate.set_defaults(action="reactivate")

    parser_rebuild = osd_sub.add_parser(
        "rebuild", help="Rebuild an OSD by destroying and creating it again."
    )
    parser_rebuild.add_argument(
        "--journal-size",
        default=fc.ceph.osd.DEFAULT_JOURNAL_SIZE,
        help="Size of journal (LVM size units allowed). "
        "Only used if rebuild target is a filestore OSD.",
    )
    parser_rebuild.add_argument(
        "--target-objectstore-type",
        "-T",
        choices=fc.ceph.osd.OBJECTSTORE_TYPES,
        help="Type of the OSD after rebuilding, defaults to keeping the current "
        "objectstore type.\nThe current type is detected automatically.",
    )
    parser_rebuild.add_argument(
        "--unsafe-destroy",
        action="store_true",
        help="Skip the check whether an OSD is safe to destroy without "
        "affecting data redundancy. This can result in data loss or cluster failure!!",
    )
    parser_rebuild.add_argument(
        "ids",
        help="IDs of OSD to migrate. Use `all` to rebuild all local OSDs.",
    )
    parser_rebuild.set_defaults(action="rebuild")

    parser_prepare_journal = osd_sub.add_parser(
        "prepare-journal", help="Create a journal volume group."
    )
    parser_prepare_journal.add_argument(
        "device", help="Block device to create a journal VG on."
    )
    parser_prepare_journal.set_defaults(action="prepare_journal")

    # Monitor commands

    mon = subparsers.add_parser("mon", help="Manage MONs.")
    mon.set_defaults(subsystem=fc.ceph.mon.Monitor, action=mon.print_usage)
    mon_sub = mon.add_subparsers()

    parser_create = mon_sub.add_parser(
        "create", help="Create and activate a local MON."
    )
    parser_create.add_argument(
        "--size", default="8g", help="Volume size to create for the MON."
    )
    parser_create.add_argument(
        "--bootstrap-cluster",
        action="store_true",
        help="Create first mon to bootstrap cluster.",
    )
    parser_create.add_argument(
        "--lvm-vg",
        help="Volume Group where the MON volume is created. "
        "Defaults to using the journal VGs.",
    )
    parser_create.set_defaults(action="create")

    parser_activate = mon_sub.add_parser(
        "activate", help="Activate the local MON."
    )
    parser_activate.set_defaults(action="activate")

    parser_deactivate = mon_sub.add_parser(
        "deactivate", help="Deactivate the local MON."
    )
    parser_deactivate.set_defaults(action="deactivate")

    parser_reactivate = mon_sub.add_parser(
        "reactivate", help="Reactivate the local MON."
    )
    parser_reactivate.set_defaults(action="reactivate")

    parser_destroy = mon_sub.add_parser(
        "destroy", help="Destroy the local MON."
    )
    parser_destroy.set_defaults(action="destroy")

    # MGR commands

    mgr = subparsers.add_parser("mgr", help="Manage MGRs.")
    mgr.set_defaults(subsystem=fc.ceph.mgr.Manager, action=mgr.print_usage)
    mgr_sub = mgr.add_subparsers()

    parser_create = mgr_sub.add_parser(
        "create", help="Create and activate a local MGR."
    )
    parser_create.add_argument(
        "--size", default="8g", help="Volume size to create for the MGR."
    )
    parser_create.add_argument(
        "--lvm-vg",
        help="Volume Group where the MGR volume is created. "
        "Defaults to using the journal VGs.",
    )
    parser_create.set_defaults(action="create")

    parser_activate = mgr_sub.add_parser(
        "activate", help="Activate the local MGR."
    )
    parser_activate.set_defaults(action="activate")

    parser_deactivate = mgr_sub.add_parser(
        "deactivate", help="Deactivate the local MGR."
    )
    parser_deactivate.set_defaults(action="deactivate")

    parser_reactivate = mgr_sub.add_parser(
        "reactivate", help="Reactivate the local MGR."
    )
    parser_reactivate.set_defaults(action="reactivate")

    parser_destroy = mgr_sub.add_parser(
        "destroy", help="Destroy the local MGR."
    )
    parser_destroy.set_defaults(action="destroy")

    # Key commands

    keys = subparsers.add_parser("keys", help="Manage keys.")
    keys.set_defaults(
        subsystem=fc.ceph.keys.KeyManager, action=keys.print_usage
    )
    keys_sub = keys.add_subparsers()

    parser_update_client_keys = keys_sub.add_parser(
        "mon-update-client-keys", help="Update the monitor key database."
    )
    parser_update_client_keys.set_defaults(action="mon_update_client_keys")

    parser_update_single_client_key = keys_sub.add_parser(
        "mon-update-single-client",
        help="Update a single client key in the mon database (OFFLINE).",
    )
    parser_update_single_client_key.add_argument(
        "id", help="client id (i.e. the hostname)"
    )
    parser_update_single_client_key.add_argument(
        "roles", action=SplitArgs, help="Which roles the client has."
    )
    parser_update_single_client_key.add_argument(
        "secret_salt", help="Secret salt for the client."
    )
    parser_update_single_client_key.set_defaults(
        action="mon_update_single_client_key"
    )

    parser_generate_client_keyring = keys_sub.add_parser(
        "generate-client-keyring",
        help="Generate and configure a keyring for the local client.",
    )
    parser_generate_client_keyring.set_defaults(
        action="generate_client_keyring"
    )

    # Log analysis commands
    logs = subparsers.add_parser("logs", help="Log analysis helpers.")
    logs.set_defaults(subsystem=fc.ceph.logs.LogTasks, action=logs.print_usage)
    logs_sub = logs.add_subparsers()

    slowreq_histogram = logs_sub.add_parser(
        "slowreq-histogram",
        help="""Slow requests histogram tool.

Reads a ceph.log file and filters by lines matching a given RE (default:
slow request). For all filtered lines that contain an OSD identifier,
the OSD identifier is counted. Prints a top-N list of OSDs having slow
requests. Useful for identifying slacky OSDs.""",
    )
    slowreq_histogram.add_argument(
        "-i",
        "--include",
        default="slow request ",
        help='include lines (default: "%(default)s")',
    )
    slowreq_histogram.add_argument(
        "-e",
        "--exclude",
        default="waiting for (degraded object|subops)",
        help='exclude lines included by -i (default: "%(default)s")',
    )
    slowreq_histogram.add_argument(
        "-n", "--first-n", help="output N worst OSDs", default=20
    )
    slowreq_histogram.add_argument(
        "filenames",
        nargs="+",
        help="ceph.log (optionally gzipped)",
        default=["/var/log/ceph/ceph.log"],
    )
    slowreq_histogram.set_defaults(action="slowreq_histogram")

    # Maintenance commands

    maint = subparsers.add_parser(
        "maintenance", help="Perform maintenance tasks."
    )
    maint.set_defaults(
        subsystem=fc.ceph.maintenance.MaintenanceTasks, action=maint.print_usage
    )
    maint_sub = maint.add_subparsers()

    parser_load_vm_images = maint_sub.add_parser(
        "load-vm-images", help="Load VM images from Hydra into cluster."
    )
    parser_load_vm_images.set_defaults(action="load_vm_images")

    parser_purge_old_snapshots = maint_sub.add_parser(
        "purge-old-snapshots", help="Purge outdated snapshots."
    )
    parser_purge_old_snapshots.set_defaults(action="purge_old_snapshots")

    parser_clean_deleted_vms = maint_sub.add_parser(
        "clean-deleted-vms", help="Remove disks from deleted VMs."
    )
    parser_clean_deleted_vms.set_defaults(action="clean_deleted_vms")

    parser_enter = maint_sub.add_parser("enter", help="Enter maintenance mode.")
    parser_enter.set_defaults(action="enter")

    parser_leave = maint_sub.add_parser("leave", help="Leave maintenance mode.")
    parser_leave.set_defaults(action="leave")

    # extract parsed arguments from object into a dict
    args = vars(parser.parse_args(args))

    subsystem_factory = args.pop("subsystem")
    action = args.pop("action")

    # print general help when no valid subcommand has been supplied
    if not (subsystem_factory and action):
        parser.print_help()
        sys.exit(1)
    # print subcommand-specific usage info
    elif callable(action) and action.__name__ == "print_usage":
        action()
        sys.exit(1)

    environment = Environment(CONFIG_FILE_PATH)
    subsystem = environment.prepare(subsystem_factory)
    action = getattr(subsystem, action)
    action_statuscode = action(**args)

    # optionally allow actions to return a statuscode
    if isinstance(action_statuscode, int):
        sys.exit(action_statuscode)
