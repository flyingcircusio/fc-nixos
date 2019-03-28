#!/usr/bin/env bash
# This script processes per-user logrotate snippets for a single user.
# The first argument given is a directory of all user logrotate configs.
# This script runs within the context of a single user and assumes his
set -e

USER="${USER:-$(whoami)}"
cfg="$1"
spool="/var/spool/logrotate"

# Run only if there actually are config files around.
if [[ -d "${cfg}" && -z $(find "${cfg}" -maxdepth 0 -empty) ]]; then
    state="${spool}/${USER}.state"
    if [[ ! -f ${state} ]]; then
        install -o "$USER" /dev/null "$state"
    fi
    expandedconf="${spool}/${USER}.conf"
    cat /etc/logrotate.options "${cfg}"/* > "${expandedconf}" &&
        logrotate -v -s "${state}" "${expandedconf}" ||
        true
fi
