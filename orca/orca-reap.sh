#!/usr/bin/env bash
# Release Orca orchestration worker terminals that Orca already settled
# ("reclaimable") but whose coordinator never ran `worker-release`.
#
# Dry-run by default: set ORCA_REAP_APPLY=1 to actually release.
# A worker is released only after it stayed reclaimable for ORCA_REAP_GRACE_MIN
# minutes across runs, so a coordinator can still reuse its terminal.
# Workspaces matching ORCA_REAP_EXCLUDE (extended regex) are never touched.
# Released workers keep their worktree and code; output stays readable with
# `orca orchestration worker-read`.

set -euo pipefail

APPLY="${ORCA_REAP_APPLY:-0}"
GRACE_MIN="${ORCA_REAP_GRACE_MIN:-30}"
EXCLUDE="${ORCA_REAP_EXCLUDE:-voice|dictation|dictado}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/orca-reap"
SEEN_FILE="$STATE_DIR/seen.tsv"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"
}

for bin in orca jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "error: $bin not found on PATH"
        exit 1
    fi
done

if ! orca status --json 2>/dev/null | jq -e '.result.runtime.reachable == true' >/dev/null; then
    log "skip: Orca runtime not reachable"
    exit 0
fi

mkdir -p "$STATE_DIR"
touch "$SEEN_FILE"

# Collect every reclaimable worker across all Runs, following pagination.
rows=""
cursor=""
while :; do
    args=(orchestration worker-list --terminal-state reclaimable --include-remote --limit 100 --json)
    if [ -n "$cursor" ]; then
        args+=(--cursor "$cursor")
    fi
    page="$(orca "${args[@]}")"
    rows+="$(jq -r '.result.workers[] | [.dispatchId, (.resource.worktreeId // "" | split("::") | last)] | @tsv' <<<"$page")"$'\n'
    cursor="$(jq -r '.result.page.nextCursor // empty' <<<"$page")"
    [ -z "$cursor" ] && break
done

now="$(date +%s)"
next_seen="$(mktemp)"
trap 'rm -f "$next_seen"' EXIT
count=0

while IFS=$'\t' read -r dispatch workspace; do
    [ -z "$dispatch" ] && continue
    count=$((count + 1))

    if [[ "$workspace" =~ $EXCLUDE ]]; then
        log "keep $dispatch ($workspace): excluded workspace"
        continue
    fi

    first_seen="$(awk -F'\t' -v d="$dispatch" '$1 == d { print $2 }' "$SEEN_FILE")"
    first_seen="${first_seen:-$now}"
    printf '%s\t%s\n' "$dispatch" "$first_seen" >>"$next_seen"

    age_min=$(((now - first_seen) / 60))
    if [ "$age_min" -lt "$GRACE_MIN" ]; then
        log "wait $dispatch ($workspace): reclaimable for ${age_min}m, grace ${GRACE_MIN}m"
        continue
    fi

    if [ "$APPLY" = "1" ]; then
        state="$(orca orchestration worker-release --dispatch "$dispatch" --json 2>&1 |
            jq -r '.result.releaseState // .error.code // "unknown"' 2>/dev/null || echo "unknown")"
        log "release $dispatch ($workspace): $state"
    else
        log "dry-run $dispatch ($workspace): would release (reclaimable for ${age_min}m)"
    fi
done <<<"$rows"

mv "$next_seen" "$SEEN_FILE"
trap - EXIT
log "done: $count reclaimable worker(s), apply=$APPLY"
