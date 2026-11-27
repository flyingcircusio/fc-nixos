#!/usr/bin/env bash

set -euo pipefail

export CEPH_ARGS="--id $HOSTNAME"

FSCHECK_CMD="xfs_repair"

# parse optional fscheck command arg
while getopts ':F:' OPT; do
    case $OPT in
        F)
            FSCHECK_CMD="$OPTARG"
            ;;
        ?)
            echo "fs-check [-F <fsck_command>] <pool> <vm>"
            echo "  shut down a VM, run a filesystem check on its root image, and start it again."
            echo "  <fsck_command> defaults to \`xfs_repair\`"
            echo "  note: <fsck_cmd> might need to be specified as an absolute path"
            echo
            echo "  Example: fs-check -F \"/run/current-system/sw/bin/fsck.ext4 -f -p\" rbd.hdd testgentoo"
            exit 1
            ;;
    esac
done

# trim CLI parameters
shift "$(($OPTIND -1))"

pool=${1?need pool}
vm=${2?need vm name}
image=${vm}.root
mountpoint=/mnt/restore/$vm

echo "FS-Check (XFS!) for ${vm} ($pool) using \`$FSCHECK_CMD\`"
echo "Ready? VM will shut down immediately."
read

echo "=== ${vm} ==="

mkdir -p $mountpoint

# Shutdown
rbd-locktool -i ${pool}/${image}
fc-directory "d.set_vm_property('${vm}', 'online', False)"
until (rbd-locktool -i ${pool}/${image}| grep None) do echo "waiting for VM to shut down ..."; sleep 5; done

device=$(rbd map ${pool}/${image})
echo Mapped to $device
mount ${device}p1 $mountpoint
umount $mountpoint
$FSCHECK_CMD ${device}p1

rbd unmap $device


echo "Start up"
rbd-locktool -i ${pool}/${image}
fc-directory "d.set_vm_property('${vm}', 'online', True)"
until (rbd-locktool -i ${pool}/${image}| grep -v None) do echo "waiting for image to be locked ..."; sleep 5; done
