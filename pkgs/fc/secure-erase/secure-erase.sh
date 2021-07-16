#!/bin/bash
set -ex

target="${1?need target device to erase}"
name="${target//\//}"
cryptsetup open --type plain -d /dev/urandom $target $name
dd if=/dev/zero of=/dev/mapper/$name bs=4M status=progress || true
cryptsetup close $name
