#!/bin/bash
set -eu

if (type tput && tput colors) >/dev/null 2>&1; then
	GOOD="$(tput sgr0)$(tput bold)$(tput setaf 2)"
	WARN="$(tput sgr0)$(tput bold)$(tput setaf 3)"
	BAD="$(tput sgr0)$(tput bold)$(tput setaf 1)"
	HILITE="$(tput sgr0)$(tput bold)$(tput setaf 6)"
	BRACKET="$(tput sgr0)$(tput bold)$(tput setaf 4)"
	NORMAL="$(tput sgr0)"
else
	GOOD=$(printf '\033[32;01m')
	WARN=$(printf '\033[33;01m')
	BAD=$(printf '\033[31;01m')
	HILITE=$(printf '\033[36;01m')
	BRACKET=$(printf '\033[34;01m')
	NORMAL=$(printf '\033[0m')
fi

info() {
	echo "${GOOD}*${NORMAL} $*"
}

warn() {
	echo "${BAD}* $*${NORMAL}"
}

usage() {
	info "Usage: $0 VM REV"
	exit 3
}

for i in "$@"; do
	if [[ "$i" == "-h" || "$i" == "--help" ]]; then
		usage
	fi
done

if [[ $# -ne 2 ]]; then
	warn "Expected two positional arguments"
	usage
fi

VM="$1"
REV="$2"

LOOPMNT="/mnt/restore/$VM"
FUSEMNT="/mnt/backy-fuse/$VM"

mkdir -p "$LOOPMNT" "$FUSEMNT"

info "Starting FUSE"
backy-fuse -d "/srv/backy/$VM" "$FUSEMNT" &
sleep 1

info "Registering loop device"
LOOPDEV=$(losetup --show -f -P "$FUSEMNT/$REV")
echo "$LOOPDEV"

cleanup() {
	umount "$LOOPMNT"; losetup -d "$LOOPDEV"; sleep 1; fusermount -u "$FUSEMNT"
}
trap cleanup ERR 1 2 3 15
LOOPPART="${LOOPDEV}p1"
while [ ! -e "$LOOPPART" ]; do
	sleep 0.2
done

info "Pre-mounting image to flush log"
mount -oloop "$LOOPPART" "$LOOPMNT"
umount "$LOOPMNT"

info "Regenerating UUID to avoid collisions"
# xfs_admin gets confused by conflicting fs labels, see PL-133416
# So use xfs_db directly.
# XXX: keep in sync with the args from the `xfs_admin` shell script
xfs_db -x -c "uuid generate" "$LOOPPART"

info "Mounting image"
mount -oloop "$LOOPPART" "$LOOPMNT"

info "Image data ready in ${HILITE}$LOOPMNT${NORMAL}"
while true; do
	echo -n "Hit Enter to terminate... "
	read _wait_for_user
	if fuser "$LOOPMNT" ; then
		echo "Directory $LOOPMNT still busy"
	else
		break
	fi
done

info "Unmounting devices"
cleanup
wait
