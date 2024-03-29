#!/usr/bin/env bash
#
# Created by Sebastian Grewe, Jammicron Technology
#

set -e

# Get count of raid arrays
RAID_DEVICES=`grep ^md -c /proc/mdstat || true`

# Get count of degraded arrays
RAID_STATUS=`grep "\[.*_.*\]" /proc/mdstat -c || true`

# Is an array currently recovering, get percentage of recovery
RAID_RECOVER=`grep recovery /proc/mdstat | awk '{print $4}' || true`
RAID_RESYNC=`grep resync /proc/mdstat | awk '{print $4}' || true`

# Check raid status
# RAID recovers --> Warning
if [[ $RAID_RECOVER ]]; then
STATUS="WARNING - Checked $RAID_DEVICES arrays, recovering : $RAID_RECOVER"
EXIT=1
elif [[ $RAID_RESYNC ]]; then
STATUS="WARNING - Checked $RAID_DEVICES arrays, resync : $RAID_RESYNC"
EXIT=1
# RAID ok
elif [[ $RAID_STATUS == "0" ]]; then
STATUS="OK - Checked $RAID_DEVICES arrays."
EXIT=0
# All else critical, better save than sorry
else
STATUS="CRITICAL - Checked $RAID_DEVICES arrays, $RAID_STATUS have FAILED"
EXIT=2
fi

# Status and quit
echo $STATUS
exit $EXIT
