#!/bin/sh

set -ex

alias ceph=./ceph

ceph -s

ceph health detail
ceph health detail --format=json | jq
ceph auth list
ceph osd df tree
ceph df
ceph osd lspools
ceph pg stat
ceph pg dump
ceph pg 675.23 query
ceph pg repair 675.23

ceph --admin-daemon /var/run/ceph/ceph-osd.0.asok config show

ceph tell osd.* injectargs '--osd-max-backfills=2'


ceph osd out 1
ceph osd in 1


ceph osd getcrushmap -o foo
ceph osd setcrushmap -i foo
