#!/usr/bin/env bash
set -euo pipefail

environment="24.04-lts-noble-numbat"
base="https://cloud-images.ubuntu.com/noble/current"
image="noble-server-cloudimg-amd64.img"

cd /tmp

if ! rbd namespace list rbd.hdd | grep -q images-ubuntu; then
	echo "ERROR: missing namespace $(images-ubuntu)"
	exit 2
fi

create_flags=""
if rbd info rbd.hdd/images-ubuntu/${environment} >& /dev/null; then
	create_flags="-n" # no create
fi

wget -q "${base}/SHA256SUMS"
checksum=$(grep $image SHA256SUMS | cut -d ' ' -f 1)

if rbd info "rbd.hdd/images-ubuntu/${environment}@rolling-${checksum}" >& /dev/null; then
	echo "OK: image already up to date"
	exit 0
fi

echo "Detected new checksum: ${checksum}"

rm -f "${image}"
echo "Downloading new image ..."
wget -q "${base}/${image}"
got_checksum=$(sha256sum "/tmp/${image}" | cut -d ' ' -f 1)
if [ "${got_checksum}" != "${checksum}" ]; then
	echo "ERROR: download checksum was ${got_checksum}, expected ${checksum}."
	exit 1
fi
echo "Storing new image in Ceph ..."
qemu-img convert -p ${create_flags} ${image} "rbd:rbd.hdd/images-ubuntu/${environment}:id=${HOSTNAME}"
rbd snap create "rbd.hdd/images-ubuntu/${environment}@rolling-${checksum}"
rbd snap protect "rbd.hdd/images-ubuntu/${environment}@rolling-${checksum}"
echo "OK: image updated"
