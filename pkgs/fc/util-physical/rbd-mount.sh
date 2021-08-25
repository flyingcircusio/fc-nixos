#!/usr/bin/env bash
set -e

usage() {
    cat <<_EOT_
Usage: $0 [-u] [-p PREFIX] POOL/VOLUME

Utility to mount/unmount a RBD volume with proper locking.  The volume will be
mounted as \${PREFIX}/\${VOLUME}. The volume must be specified together with its
pool name. On success, this tool will output the full path to the mount point.

Options:
    -u|--unmount|--umount   unmount volume (prefix must match the one given at
                            mount time)
    -p|--prefix PREFIX      mount point prefix, defaults to /mnt/rbd
    -h|--help               this help screen
_EOT_
}

export CEPH_CONF="/etc/ceph/ceph.conf"
export CEPH_ARGS="--id $HOSTNAME -c $CEPH_CONF"

PREFIX="/mnt/rbd"
UMOUNT=0
opts=$(getopt -o hup: --long help,umount,unmount,prefix: -- "$@")
eval set -- "$opts"
while true; do
    case "$1" in
        -h|--help)
            usage
            exit;;
        -u|--umount|--unmount)
            UMOUNT=1
            shift;;
        -p|--prefix)
            PREFIX="$2"
            shift 2;;
        --)
            shift
            break;;
        *)
            echo "$0: internal getopt error" >&2
            exit 70
    esac
done
if [[ $# != 1 ]]; then
    echo "$0: no volume name given" >&1
    usage
    exit 64
fi
VOLUME="$1"
if ! [[ "$VOLUME" == */* ]]; then
    echo "$0: volume specification must be in the format POOL/VOLUME" >&2
    exit 64
fi

if [[ "$VOLUME" == *@* ]]; then
    MOUNT_SNAPSHOT=1
    BASE_VOLUME="${VOLUME%@*}"
else
    MOUNT_SNAPSHOT=0
    BASE_VOLUME="$VOLUME"
fi

if ! rbd info "$VOLUME" &>/dev/null; then
    echo "$0: volume ${VOLUME} not found" &>2
    exit 66
fi

MOUNTPOINT="${PREFIX}/${VOLUME}"

do_mount() {
    rbd-locktool -l "$BASE_VOLUME" >&2
    CEPH_DEV=$(rbd map "$VOLUME")
    # Sleep for race condition to allow device names to settle
    sleep 1
    if ! mountpoint -q "$MOUNTPOINT"; then
        mkdir -p "$MOUNTPOINT"
        local mount_opts=""
        if ((MOUNT_SNAPSHOT)); then
            mount_opts=",ro"
        fi
        mount -o noatime${mount_opts} "${CEPH_DEV}p1" "$MOUNTPOINT"
    fi
    echo "$MOUNTPOINT"
}

do_umount() {
    if mountpoint -q "$MOUNTPOINT"; then
        umount "$MOUNTPOINT"
    fi
    rmdir "$MOUNTPOINT" 2>/dev/null || true
    rmdir "${MOUNTPOINT%/*}" 2>/dev/null || true
    rmdir "$PREFIX" 2>/dev/null || true
    if [[ -e "$CEPH_DEV" ]]; then
        rbd unmap "$CEPH_DEV"
    fi
    rbd-locktool -u "$BASE_VOLUME"
}

if ((UMOUNT)); then
    do_umount
else
    do_mount
fi
