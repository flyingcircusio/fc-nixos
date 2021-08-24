import argparse
import os
import socket
import sys

import fc.ceph.keys
import fc.ceph.maintenance
import fc.ceph.manage


def main(args=sys.argv[1:]):
    hostname = socket.gethostname()

    # Fix l18n so that we can count on output from external utilities.
    if 'LC_ALL' in os.environ:
        del os.environ['LC_ALL']
    os.environ['LANGUAGE'] = os.environ['LANG'] = 'en_US.utf8'

    parser = argparse.ArgumentParser()
    parser.set_defaults(subsystem=None, action=None)

    subparsers = parser.add_subparsers()

    osd = subparsers.add_parser('osd', help='Manage OSDs.')
    osd.set_defaults(subsystem=fc.ceph.manage.OSDManager)
    osd_sub = osd.add_subparsers()

    parser_destroy = osd_sub.add_parser('destroy', help='Destroy an OSD.')
    parser_destroy.add_argument(
        'ids',
        help='IDs of OSD to destroy. Use `all` to destroy all local OSDs.')
    parser_destroy.set_defaults(action='destroy')

    parser_activate = osd_sub.add_parser(
        'create', help='Create activate an OSD.')
    parser_activate.add_argument('device', help='Blockdevice to use')
    parser_activate.add_argument(
        '--journal',
        default='external',
        choices=['external', 'internal'],
        help='Type of journal (on same disk or external)')
    parser_activate.add_argument(
        '--journal-size', default=0, type=int, help='Size of journal.')
    parser_activate.add_argument(
        '--crush-location', default=f'host={hostname}')
    parser_activate.set_defaults(action='create')

    parser_activate = osd_sub.add_parser(
        'activate', help='Activate one or more OSDs.')
    parser_activate.add_argument(
        'ids',
        help='IDs of OSD to activate. Use `all` to activate all local OSDs.')
    parser_activate.set_defaults(action='activate')

    parser_deactivate = osd_sub.add_parser(
        'deactivate', help='Deactivate an OSD.')
    parser_deactivate.add_argument(
        'ids',
        help='IDs of OSD to deactivate. '
        'Use `all` to deactivate all local OSDs.')
    parser_deactivate.set_defaults(action='deactivate')

    parser_reactivate = osd_sub.add_parser(
        'reactivate', help='Reactivate an OSD.')
    parser_reactivate.add_argument(
        'ids',
        help='IDs of OSDs to reactivate (activate and deactivate). '
        'Use `all` to reactivate all local OSDs.')
    parser_reactivate.set_defaults(action='reactivate')

    parser_rebuild = osd_sub.add_parser(
        'rebuild', help='Rebuild an OSD by destroying and creating it again.')
    parser_rebuild.add_argument(
        'ids',
        help='IDs of OSD to migrate. Use `all` to rebuild all local OSDs.')
    parser_rebuild.set_defaults(action='rebuild')

    parser_prepare_journal = osd_sub.add_parser(
        'prepare-journal', help='Create a journal volume group.')
    parser_prepare_journal.add_argument(
        'device', help='Block device to create a journal VG on.')
    parser_prepare_journal.set_defaults(action='prepare_journal')

    # Monitor commands

    mon = subparsers.add_parser('mon', help='Manage MONs.')
    mon.set_defaults(subsystem=fc.ceph.manage.Monitor)
    mon_sub = mon.add_subparsers()

    parser_create = mon_sub.add_parser(
        'create', help='Create and activate a local MON.')
    parser_create.add_argument(
        '--size', default='8g', help='Volume size to create for the MON.')
    parser_create.set_defaults(action='create')

    parser_activate = mon_sub.add_parser(
        'activate', help='Activate the local MON.')
    parser_activate.set_defaults(action='activate')

    parser_deactivate = mon_sub.add_parser(
        'deactivate', help='Deactivate the local MON.')
    parser_deactivate.set_defaults(action='deactivate')

    parser_reactivate = mon_sub.add_parser(
        'reactivate', help='Reactivate the local MON.')
    parser_reactivate.set_defaults(action='reactivate')

    parser_destroy = mon_sub.add_parser(
        'destroy', help='Destroy the local MON.')
    parser_destroy.set_defaults(action='destroy')

    # Key commands

    keys = subparsers.add_parser('keys', help='Manage keys.')
    keys.set_defaults(subsystem=fc.ceph.keys.KeyManager)
    keys_sub = keys.add_subparsers()

    parser_create = keys_sub.add_parser(
        'mon-update-client-keys', help='Update the monitor key database.')
    parser_create.set_defaults(action='mon_update_client_keys')

    parser_activate = keys_sub.add_parser(
        'generate-client-keyring',
        help='Generate and configure a keyring for the local client.')
    parser_activate.set_defaults(action='generate_client_keyring')

    # Maintenance commands

    maint = subparsers.add_parser(
        'maintenance', help='Perform maintenance tasks.')
    maint.set_defaults(subsystem=fc.ceph.maintenance.MaintenanceTasks)
    maint_sub = maint.add_subparsers()

    parser_load_vm_images = maint_sub.add_parser(
        'load-vm-images', help='Load VM images from Hydra into cluster.')
    parser_load_vm_images.set_defaults(action='load_vm_images')

    parser_purge_old_snapshots = maint_sub.add_parser(
        'purge-old-snapshots', help='Purge outdated snapshots.')
    parser_purge_old_snapshots.set_defaults(action='purge_old_snapshots')

    parser_clean_deleted_vms = maint_sub.add_parser(
        'clean-deleted-vms', help='Remove disks from deleted VMs.')
    parser_clean_deleted_vms.set_defaults(action='clean_deleted_vms')

    args = vars(parser.parse_args(args))

    subsystem = args.pop('subsystem')
    action = args.pop('action')

    if not (subsystem and action):
        parser.print_help()
        sys.exit(1)

    manager = subsystem()
    getattr(manager, action)(**args)
