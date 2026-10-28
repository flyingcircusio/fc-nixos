#!/usr/bin/env bash
# Move models away from this machine before it enters maintenance and let the
# proxy place them here again afterwards (PL-135777).
#
# This is called by the fc-agent maintenance hooks (see
# `flyingcircus.agent.maintenance`). The inference server keeps serving
# requests until the proxy removed it from its placement map and unloaded all
# models; the maintenance request is visible in
# `GET /manager/maintenance` as the `phase` field.
#
# Environment:
#   SKVAIDER_MAINTENANCE_URL           Management URL of the inference server.
#   SKVAIDER_MAINTENANCE_TIMEOUT       Seconds to wait for the models to move
#                                      away (default: 300).
#   SKVAIDER_MAINTENANCE_POLL_INTERVAL Seconds between phase polls (default: 2).

set -euo pipefail

# fc-agent interprets these exit codes (fc.maintenance.state).
readonly EXIT_TEMPFAIL=75

url="${SKVAIDER_MAINTENANCE_URL:?SKVAIDER_MAINTENANCE_URL must be set}"
wait_seconds="${SKVAIDER_MAINTENANCE_TIMEOUT:-300}"
poll_interval="${SKVAIDER_MAINTENANCE_POLL_INTERVAL:-2}"

log() {
    printf 'skvaider-maintenance: %s\n' "$*"
}

# Request maintenance mode. Must be idempotent: the server keeps the original
# request time if it is already in maintenance.
request_maintenance() {
    curl --silent --show-error --fail --max-time 10 \
        --request POST \
        --header 'Content-Type: application/json' \
        --data "{\"reason\": \"fc-agent maintenance on $(hostname)\"}" \
        "$url" >/dev/null
}

# Ask the server whether we may continue. Returns the phase, or an empty
# string when the server cannot be reached.
maintenance_phase() {
    curl --silent --show-error --fail --max-time 10 "$url" 2>/dev/null \
        | jq -r '.phase // empty' 2>/dev/null \
        || true
}

enter() {
    local rc phase deadline

    rc=0
    request_maintenance || rc=$?
    case "$rc" in
        0) ;;
        7)
            # Connection refused: the inference server is not running, so
            # there are no models that could be moved away.
            log "inference server not reachable, nothing to move away"
            return 0
            ;;
        *)
            log "could not request maintenance mode (curl exit $rc), postponing"
            return "$EXIT_TEMPFAIL"
            ;;
    esac

    log "requested maintenance mode, waiting up to ${wait_seconds}s for models to move away"
    deadline=$((SECONDS + wait_seconds))
    while ((SECONDS < deadline)); do
        phase="$(maintenance_phase)"
        case "$phase" in
            drained)
                log "no models left on this machine, maintenance may continue"
                return 0
                ;;
            none)
                # The server restarted and lost the request: ask again.
                log "maintenance request was lost by a restart, requesting again"
                request_maintenance || true
                ;;
            requested | draining | "") ;;
            *)
                log "unexpected maintenance phase '${phase}', waiting"
                ;;
        esac
        sleep "$poll_interval"
    done

    log "models are still running after ${wait_seconds}s, postponing maintenance"
    return "$EXIT_TEMPFAIL"
}

leave() {
    local rc phase deadline

    rc=0
    curl --silent --show-error --fail --max-time 10 --request DELETE "$url" \
        >/dev/null || rc=$?
    case "$rc" in
        0) ;;
        7)
            log "inference server not reachable, nothing to do"
            return 0
            ;;
        *)
            log "could not leave maintenance mode (curl exit $rc)"
            return 1
            ;;
    esac

    deadline=$((SECONDS + 30))
    while ((SECONDS < deadline)); do
        phase="$(maintenance_phase)"
        if [[ "$phase" == "none" ]]; then
            log "left maintenance mode, models may be placed here again"
            return 0
        fi
        sleep 1
    done

    log "server is still in maintenance mode after 30s"
    return 1
}

case "${1:-}" in
    enter) enter ;;
    leave) leave ;;
    *)
        log "usage: $0 enter|leave"
        exit 2
        ;;
esac
