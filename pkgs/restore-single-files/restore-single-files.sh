#!/bin/bash
set -e

if (type tput && [[ "$(tput colors)" -gt 0 ]]) >/dev/null 2>&1; then
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

info()
{
	printf "${GOOD}*${NORMAL} $*\n"
}

warn()
{
	printf "${BAD}* $*${NORMAL}\n"
}

VM="${1?need VM name}"
REV="${2?need revision identifier}"

if [[ -z "$VM" ]]; then
	warn "VM or revision not specified"
	echo "Usage: $0 VM REV"
	exit 3
fi

LOOPMNT="/mnt/restore/$VM"
FUSEMNT="/mnt/backy-fuse/$VM"

mkdir -p "$LOOPMNT" "$FUSEMNT"

info "Starting FUSE"
backy-fuse -d /srv/backy/$VM $FUSEMNT &
sleep 1

info "Registering loop device"
LOOPDEV=$(losetup --show -f -P $FUSEMNT/$REV)
echo $LOOPDEV

TERMINATE="umount $LOOPMNT; losetup -d $LOOPDEV; sleep 1; fusermount -u $FUSEMNT"
trap "$TERMINATE" ERR 1 2 3 5 15
LOOPPART="${LOOPDEV}p1"
while [ ! -e $LOOPPART ]; do
	sleep 0.2
done

info "Mounting image"
mount -oloop ${LOOPPART} $LOOPMNT

info "Image data ready in ${HILITE}$LOOPMNT${NORMAL}"
while true; do
	echo -n "Hit Enter to terminate... "
	read _wait_for_user
	if fuser $LOOPMNT ; then
		echo "Directory $LOOPMNT still busy"
	else
		break
	fi
done

info "Unmounting devices"
eval $TERMINATE
wait
