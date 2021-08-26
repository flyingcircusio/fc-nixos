#!/usr/bin/env bash
set -e

oldpool=${1?need old pool}
newpool=${2?need new pool}
vm=${3?need vm name}
image=${vm}.root

echo "About to migrate the following VMs:"
echo "* ${oldpool}/${vm} -> ${newpool}/${vm}"

echo "Ready? VM will shut down immediately"
read

echo "=== ${vm} ==="

# Shutdown
rbd-locktool -i ${oldpool}/${image}
fc-directory "d.set_vm_property('${vm}', 'online', False)"
until (rbd-locktool -i ${oldpool}/${image}| grep None) do echo "waiting for VM to shut down ..."; sleep 5; done

echo "Cloning"
echo -n "Unprotecting pre-existing migration snapshot: "
rbd snap unprotect $oldpool/$image@migration || true
echo -n "Removing pre-existing migration snapshot: "
rbd snap rm $oldpool/$image@migration || true
rbd snap create $oldpool/$image@migration
rbd snap protect $oldpool/$image@migration
rbd clone $oldpool/$image@migration $newpool/$image

echo "Start up"
rbd-locktool -i ${oldpool}/${image}
fc-directory "d.set_vm_property('${vm}', 'rbd_pool', '${newpool}')"
fc-directory "d.set_vm_property('${vm}', 'online', True)"
until (rbd-locktool -i ${oldpool}/${image}| grep None) do echo "Old image still locked ..."; sleep 5; done
until (rbd-locktool -i ${newpool}/${image}| grep -v None) do echo "waiting for new image to be locked ..."; sleep 5; done

echo "Flatten clone"
rbd flatten $newpool/$image

echo "Remove old image"
rbd snap unprotect $oldpool/$image@migration
rbd snap purge ${oldpool}/${vm}.root || true
rbd snap purge ${oldpool}/${vm}.tmp || true
rbd snap purge ${oldpool}/${vm}.swap || true
rbd rm ${oldpool}/${vm}.root
rbd rm ${oldpool}/${vm}.tmp
rbd rm ${oldpool}/${vm}.swap
