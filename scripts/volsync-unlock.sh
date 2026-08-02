#!/usr/bin/env bash
# Clear a stale restic lock on a VolSync ReplicationSource.
#
# When a mover pod dies mid-run (node reboot, CNI outage, eviction) it leaves its
# restic lock behind. Every later sync then backs up fine and fails at `forget`,
# so VolSync never records the sync as complete: lastSyncTime freezes, pruning
# stops, and retention silently stops being enforced. Snapshots keep landing, so
# nothing looks broken until the repo has grown for weeks.
#
# VolSync runs `restic unlock` when spec.restic.unlock changes value, and mirrors
# that value into status.restic.lastUnlocked once the unlock has actually run. It
# only unlocks during a sync, so this waits for the next scheduled trigger.
#
# Usage:
#   scripts/volsync-unlock.sh --stuck            # list sources that look frozen
#   scripts/volsync-unlock.sh <app> [namespace]  # unlock one source and wait

set -euo pipefail

POLL_INTERVAL="${VOLSYNC_UNLOCK_POLL:-30}"
# Default trigger is hourly; allow a full cycle plus slack before giving up.
TIMEOUT="${VOLSYNC_UNLOCK_TIMEOUT:-4200}"

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# List ReplicationSources whose last successful sync is suspiciously old.
list_stuck() {
    echo "Checking ReplicationSources for frozen syncs..."
    kubectl get replicationsource -A -o json |
        jq -r --arg now "$(date -u +%s)" '
            .items[]
            | ((.status.lastSyncTime // "1970-01-01T00:00:00Z") | fromdateiso8601) as $last
            | (((($now | tonumber) - $last) / 86400) | floor) as $age
            | select($age > 1)
            | "\($age)d\t\(.metadata.namespace)/\(.metadata.name)\t\(.status.lastSyncTime // "never")"
        ' | sort -rn | awk -F'\t' '{printf "  %-6s %-40s last=%s\n", $1, $2, $3}'
}

[[ $# -eq 0 ]] && usage 1
[[ "$1" == "-h" || "$1" == "--help" ]] && usage 0

if [[ "$1" == "--stuck" ]]; then
    list_stuck
    exit 0
fi

APP="$1"
NAMESPACE="${2:-default}"

if ! kubectl get replicationsource -n "$NAMESPACE" "$APP" >/dev/null 2>&1; then
    echo "error: no ReplicationSource $NAMESPACE/$APP" >&2
    echo "hint: run '$0 --stuck' to list sources, or pass the namespace as \$2" >&2
    exit 1
fi

TOKEN="manual-$(date -u +%Y%m%dT%H%M%SZ)"

echo "ReplicationSource: $NAMESPACE/$APP"
echo "  lastSyncTime:  $(kubectl get replicationsource -n "$NAMESPACE" "$APP" -o jsonpath='{.status.lastSyncTime}')"
echo "  lastUnlocked:  $(kubectl get replicationsource -n "$NAMESPACE" "$APP" -o jsonpath='{.status.restic.lastUnlocked}')"
echo "  unlock token:  $TOKEN"

kubectl patch replicationsource -n "$NAMESPACE" "$APP" --type merge \
    -p "{\"spec\":{\"restic\":{\"unlock\":\"$TOKEN\"}}}" >/dev/null
echo "Patched spec.restic.unlock; waiting for the next scheduled sync to run it."

deadline=$(( $(date -u +%s) + TIMEOUT ))
while [[ $(date -u +%s) -lt $deadline ]]; do
    sleep "$POLL_INTERVAL"

    last_unlocked=$(kubectl get replicationsource -n "$NAMESPACE" "$APP" \
        -o jsonpath='{.status.restic.lastUnlocked}' 2>/dev/null || true)
    if [[ "$last_unlocked" == "$TOKEN" ]]; then
        echo
        echo "Unlocked. status.restic.lastUnlocked=$TOKEN"
        kubectl get replicationsource -n "$NAMESPACE" "$APP" \
            -o jsonpath='  lastSyncTime: {.status.lastSyncTime}{"\n"}  lastPruned:   {.status.restic.lastPruned}{"\n"}'
        exit 0
    fi

    # This field is not in Git, so a Flux reconcile can strip it before the sync
    # fires. Re-assert rather than silently waiting out the timeout.
    current=$(kubectl get replicationsource -n "$NAMESPACE" "$APP" \
        -o jsonpath='{.spec.restic.unlock}' 2>/dev/null || true)
    if [[ "$current" != "$TOKEN" ]]; then
        echo "  spec.restic.unlock was reverted (likely Flux drift correction); re-applying"
        kubectl patch replicationsource -n "$NAMESPACE" "$APP" --type merge \
            -p "{\"spec\":{\"restic\":{\"unlock\":\"$TOKEN\"}}}" >/dev/null
    fi

    printf '.'
done

echo
echo "error: timed out after ${TIMEOUT}s waiting for status.restic.lastUnlocked=$TOKEN" >&2
echo "The sync may not have triggered yet. Check the mover pod:" >&2
echo "  kubectl logs -n $NAMESPACE -l volsync.backube/replication-source=$APP --tail=40" >&2
exit 1
