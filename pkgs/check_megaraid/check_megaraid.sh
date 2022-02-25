#!/bin/bash

# Uses MegaCli to check the status of disks attached to an LSI controller.
# Optional argument: [ --html | --newline ] [ --skip-offline-check ] [ --disable-other-error-count ]
# Bugs: this check will probably fail if you have more than one adapter in a host.
# 2013-12-03 - Onno - Created.
# 2013-12-05 - Onno - Added output format option.
# 2013-12-06 - Onno - Added check for missing disks.
# 2013-12-06 - Onno - Added rebuild progress indication.
# 2013-12-06 - Onno - Detect more firmware states.
# 2013-12-23 - Alexander - Fixed syntax errors in the check for missing disks.
# 2013-12-23 - Alexander - Changed Media Errors and Other Errors from CRITICAL to WARNING.
# 2014-04-14 - invokr - Fail when running as non-root user; no longer failing on drives marked as hotspare
# 2014-08-20 - a-nldisr - Get S/N for Fujitsu systems.
# 2014-08-25 - Onno - Added -NoLog to prevent /MegaSAS.log filling up partition. Thanks to Rogier for bug report.
# 2016-05-12 - Eduardo - Check whether RAID controller is offline
# 2017-11-21 - Svamberg - Add new option for skipping if is RAID controller offline
# 2017-11-21 - Svamberg - Add JBOD to filter for Firmware state
# 2017-11-21 - Svamberg - Add option to disable check of Other Error Count

# Only runnable for root
if [[ $EUID -ne 0 ]];
    then
        echo "This script must be run as root" 1>&2
        exit 1
    fi

DETECT_PREDICTIVE_FAILURE='yes'

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

MEGACLI=MegaCli64

OPT_SKIPOFFLINECHECK="0"
OPT_DISABLEOTHERERRORCOUNT="0"
for i in $@; do
  case "$i" in
    "--html"|"-h")
      LINEFEED="<br>"
      ;;
    "--newline"|"-n")
      LINEFEED="\n"
      ;;
    "--skip-offline-check")
      OPT_SKIPOFFLINECHECK="1"
      ;;
    "--disable-other-error-count")
      OPT_DISABLEOTHERERRORCOUNT="1"
      ;;
    *)
      LINEFEED=" --- "
  esac
done

# Check whether RAID controller is offline
if [  "$OPT_SKIPOFFLINECHECK" -eq "0" ]; then
  if dmesg | egrep --silent 'rejecting I/O to offline device' ; then
    echo 'RAID controller is offline'
    exit $STATE_CRITICAL
  fi
fi

# ToDo: iterate over all available adapters. For now, assume there's only one.
ADAPTER=0

# Depending on Vendor register the serialnumber
for SYSTEM_VENDOR in `dmidecode |grep -i Vendor -A 0|sed -e 's/.*: //'` ; do
  if [ $SYSTEM_VENDOR != "FUJITSU" ] ; then
    SYSTEM_SN=`dmidecode | grep 'Base Board Information' -A 5 | grep 'Serial Number' | sed -e 's/.*: //'`
  else
    SYSTEM_SN=`dmidecode | grep 'System Information' -A 5 | grep 'Serial Number' | sed -e 's/.*: //'`
  fi
done

REPORT=""

# Report virtual drive issues (partially degraded, degraded)
for VIRTUAL_DRIVE in `$MEGACLI -LDInfo -Lall -a$ADAPTER -NoLog | grep -o 'Virtual Drive: [0-9]\+' | sed -e 's/.*: //'` ; do
  LDINFO=`$MEGACLI -LDInfo -L${VIRTUAL_DRIVE} -a$ADAPTER -NoLog`
  SIZE=`echo "$LDINFO" | grep '^Size' | sed -e 's/.*: //'`
  STATE=`echo "$LDINFO" | grep '^State' | sed -e 's/.*: //'`
  if [ "$STATE" != "Optimal" ] ; then
    if [ -z "$REPORT" ] ; then
      REPORT="Virtual drive $VIRTUAL_DRIVE ($SIZE): $STATE"
    else
      REPORT="${REPORT}${LINEFEED}Virtual drive $VIRTUAL_DRIVE ($SIZE): $STATE"
    fi
  fi
done

# Report missing disks
MISSING_DISK_INFO=`$MEGACLI -PdGetMissing -a$ADAPTER -NoLog`
if echo "$MISSING_DISK_INFO" | grep --silent 'Adapter.*Missing Physical drives' ; then
  while read line ; do
    NUMBER=`echo "$line" | awk '{print $1}'`
    ARRAY=`echo "$line" | awk '{print $2}'`
    ROW=`echo "$line" | awk '{print $3}'`
    SIZE=`echo "$line" | awk '{print $4}'`
    UNIT=`echo "$line" | awk '{print $5}'`
    MISSING_REPORT="Missing disk: Nr=$NUMBER Array=$ARRAY Row=$ROW Size=$SIZE $UNIT"
    if [ -z "$REPORT" ] ; then
      REPORT="$MISSING_REPORT"
    else
      REPORT="${REPORT}${LINEFEED}${MISSING_REPORT}"
    fi
  done < <(echo "$MISSING_DISK_INFO" | grep -o '[0-9]\+[[:space:]]\+[0-9]\+[[:space:]]\+[0-9]\+[[:space:]]\+[0-9]\+[[:space:]]*[KMGT]B')
fi

# Report physical drive errors
ERRORSTATE=$STATE_OK
for ENCLOSURE_ID in `$MEGACLI -PDList -a$ADAPTER -NoLog | grep "Enclosure Device" | awk '{print $4}' | sort -nu` ;do
  for SLOT in `$MEGACLI -PDList -a$ADAPTER -NoLog | grep -A 1 "Enclosure Device ID: $ENCLOSURE_ID" | grep "Slot Number" | awk '{print $3}'` ; do
    DISKINFO=`$MEGACLI -pdinfo -PhysDrv [$ENCLOSURE_ID:$SLOT] -a$ADAPTER -NoLog`
    DISK_TYPE=`echo "$DISKINFO" | grep 'PD Type:' | sed -e 's/.*: //'`
    DISK_WWN=`echo "$DISKINFO" | grep 'WWN:' | sed -e 's/.*: //'`
    DISK_SERIAL=`echo "$DISKINFO" | grep 'Inquiry Data:' | sed -e 's/.*: //'`
    SIZE=`echo "$DISKINFO" | grep 'Raw Size:' | sed -e 's/.*: //' | sed -e 's/ \[0x.*//'`
    if [ "$DETECT_PREDICTIVE_FAILURE" = "yes" ] ; then
      PREDICTIVE_FAILURE_REGEX='\|Predictive Failure'
    else
      PREDICTIVE_FAILURE_REGEX=''
    fi

    if [ "$OPT_DISABLEOTHERERRORCOUNT" -eq "0" ] ; then
      ERRORLINES=`echo "$DISKINFO" | grep 'Count: [1-9]\|Firmware state:' | grep -v "Firmware state: Online\|Firmware state: JBOD\|Firmware state: Hotspare$PREDICTIVE_FAILURE_REGEX"`
    else
      ERRORLINES=`echo "$DISKINFO" | grep 'Count: [1-9]\|Firmware state:' | grep -v "Firmware state: Online\|Firmware state: JBOD\|Firmware state: Hotspare$PREDICTIVE_FAILURE_REGEX\|Other Error Count:"`
    fi

    if [ -n "$ERRORLINES" ] ; then
      NUMBER_OF_MEDIA_AND_OTHER_ERRORS=0
      NUMBER_OF_ERRORLINES=0
      DISKREPORT=""
      while read line ; do
        let NUMBER_OF_ERRORLINES=$NUMBER_OF_ERRORLINES+1
        if echo "$line" | grep --silent 'Error Count' ; then
          let NUMBER_OF_MEDIA_AND_OTHER_ERRORS=$NUMBER_OF_MEDIA_AND_OTHER_ERRORS+1
        fi
        if echo "$line" | grep --silent 'Rebuild' ; then
          REBUILD_PROGRESS=`$MEGACLI -pdrbld -showprog -physdrv [$ENCLOSURE_ID:$SLOT] -a$ADAPTER -NoLog | grep -o 'Completed [0-9]\+%'`
          line="$line ($REBUILD_PROGRESS)"
        fi
        if [ -z "$DISKREPORT" ] ; then
          DISKREPORT=`echo Enclosure/slot [$ENCLOSURE_ID:$SLOT] WWN=$DISK_WWN $DISK_SERIAL "($SIZE)" - $line`
        else
          DISKREPORT="$DISKREPORT - `echo $line`"
        fi
      done < <(echo "$ERRORLINES")
      if [ $NUMBER_OF_ERRORLINES -eq $NUMBER_OF_MEDIA_AND_OTHER_ERRORS ] ; then
        ERRORSTATE=$STATE_WARNING
      else
        ERRORSTATE=$STATE_CRITICAL
      fi
      if [ -z "$REPORT" ] ; then
        REPORT="$DISKREPORT"
      else
        REPORT="${REPORT}${LINEFEED}${DISKREPORT}"
      fi
    fi
  done
done


if [ -z "$REPORT" ] ; then
  echo "OK - System S/N=$SYSTEM_SN: no disk problems found."
  exit $STATE_OK
else
  if [ $ERRORSTATE -eq $STATE_WARNING ] ; then
    echo -e "WARNING - System S/N=$SYSTEM_SN: ${LINEFEED}${REPORT}"
    exit $STATE_WARNING
  else
    echo -e "CRITICAL - System S/N=$SYSTEM_SN: ${LINEFEED}${REPORT}"
    exit $STATE_CRITICAL
  fi
fi
