#!/bin/bash
# The assertion helpers are invoked indirectly through "${@:3}" in want(), so
# the linter cannot see the call sites. SC2317 and SC2329 are the same
# "unreachable function" finding, renumbered between versions; pre-commit pins
# an older one than Homebrew ships.
# shellcheck disable=SC2317,SC2329

# Golden-input tests for gentle-ai-overrides/reconcile.sh.
#
# The reconciler edits ~/.claude/CLAUDE.md, so every case runs against a
# throwaway CLAUDE_DIR instead. That is what the CLAUDE_DIR override in
# reconcile.sh exists for — CI has no ~/.claude, and a test that mutated the
# real one would be worse than no test.

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
R="$HERE/gentle-ai-overrides/reconcile.sh"
BLOCK="$HERE/gentle-ai-overrides/CLAUDE.local-overrides.md"
SENTINEL='<!-- dotfiles:local-sdd-overrides -->'
fail=0

# Assertions take the command itself rather than a bare $?, so the exit status
# they read is always the one they asked for.
want()    { # want <label> <detail> <cmd...>
  if "${@:3}" > /dev/null 2>&1; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s — %s\n' "$1" "$2"; fail=1; fi
}
want_not() { # want_not <label> <detail> <cmd...>
  if "${@:3}" > /dev/null 2>&1; then printf 'FAIL  %s — %s\n' "$1" "$2"; fail=1
  else printf 'ok    %s\n' "$1"; fi
}

# A CLAUDE.md shaped like the real one: gentle-ai regions, nothing of ours.
seed_dir() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/agents"
  cat > "$d/CLAUDE.md" <<'EOF'
<!-- gentle-ai:persona -->
## Rules
persona body
<!-- /gentle-ai:persona -->
<!-- gentle-ai:agent-routing -->
## Implementation Routing
routing body
<!-- /gentle-ai:agent-routing -->
EOF
  printf '%s' "$d"
}

seed_agent() { # seed_agent <dir> <name> [extra-frontmatter-line]
  cat > "$1/agents/$2.md" <<EOF
---
name: $2
description: test agent
model: sonnet
${3:-}
---

Body text.
EOF
}

run() { CLAUDE_DIR="$1" bash "$R" "${@:2}" > /dev/null 2>&1; }

# Helpers used as assertion commands.
count_is()   { [ "$(rg -cN "$2" "$1")" -eq "$3" ]; }
line_of()    { rg -n "$2" "$1" | tail -1 | cut -d: -f1; }
block_after_markers() {
  [ "$(line_of "$1" "^${SENTINEL}\$")" -gt "$(line_of "$1" '^<!-- /gentle-ai:')" ]
}
memory_inside_frontmatter() {
  local fence mem
  fence=$(rg -n '^---$' "$1" | sed -n 2p | cut -d: -f1)
  mem=$(rg -n '^memory: project$' "$1" | cut -d: -f1)
  [ -n "$mem" ] && [ "$mem" -lt "$fence" ]
}
same_bytes() { [ "$(md5 -q "$1")" = "$2" ]; }

echo "== CLAUDE.md block =="

d="$(seed_dir)"
run "$d"
want "block is injected on a fresh file" "sentinel absent" \
  rg -qNF "$SENTINEL" "$d/CLAUDE.md"

# The block must land AFTER every gentle-ai close marker — inside a region it
# would be wiped by the next sync, which is the whole failure this guards.
want "block lands outside every gentle-ai region" "block sits above a marker" \
  block_after_markers "$d/CLAUDE.md"

want "gentle-ai markers survive the splice" "marker count changed" \
  count_is "$d/CLAUDE.md" '^<!-- gentle-ai:' 2

before="$(md5 -q "$d/CLAUDE.md")"
run "$d"
want "second run changes nothing" "file mutated on a clean run" \
  same_bytes "$d/CLAUDE.md" "$before"

want "block is never duplicated" "more than one sentinel" \
  count_is "$d/CLAUDE.md" "^${SENTINEL}\$" 1
rm -rf "$d"

# A stale block — an older revision of the rules — is replaced in place.
d="$(seed_dir)"
printf '\n%s\n## Old rules\nstale\n<!-- /dotfiles:local-sdd-overrides -->\n' "$SENTINEL" >> "$d/CLAUDE.md"
run "$d"
want_not "a stale block is replaced, not kept" "old content still present" \
  rg -qNF '## Old rules' "$d/CLAUDE.md"

want "the replacement carries the tracked rules" "tracked content missing" \
  rg -qNF 'L1. One test task per spec scenario' "$d/CLAUDE.md"

want "replacing keeps the gentle-ai regions intact" "marker count changed" \
  count_is "$d/CLAUDE.md" '^<!-- gentle-ai:' 2

want "replacing keeps the surrounding body" "body lost in the splice" \
  rg -qNF 'routing body' "$d/CLAUDE.md"
rm -rf "$d"

echo
echo "== safety =="

# Half-written CLAUDE.md: an interrupted sync. Editing it could splice into a
# region that is about to be rewritten, so the reconciler must refuse.
d="$(seed_dir)"
printf '<!-- gentle-ai:orphan -->\ndangling\n' >> "$d/CLAUDE.md"
before="$(md5 -q "$d/CLAUDE.md")"
want_not "unbalanced gentle-ai markers exit non-zero" "it proceeded anyway" \
  run "$d"
want "unbalanced markers leave the file untouched" "file was modified anyway" \
  same_bytes "$d/CLAUDE.md" "$before"
rm -rf "$d"

echo
echo "== reviewer agents =="

d="$(seed_dir)"
seed_agent "$d" jd-judge-a
seed_agent "$d" review-risk 'memory: project'
run "$d"

want "memory: project is added when absent" "not added" \
  rg -qN '^memory: project$' "$d/agents/jd-judge-a.md"

want "an agent that already has it is left alone" "duplicated" \
  count_is "$d/agents/review-risk.md" '^memory: project$' 1

want "the key lands inside the frontmatter" "it landed in the body" \
  memory_inside_frontmatter "$d/agents/jd-judge-a.md"

want "the agent body is preserved" "body lost" \
  rg -qN '^Body text\.$' "$d/agents/jd-judge-a.md"

want "an agent gentle-ai has not installed is skipped, not created" "a file appeared" \
  test ! -e "$d/agents/review-reliability.md"
rm -rf "$d"

echo
echo "== --check =="

d="$(seed_dir)"
seed_agent "$d" jd-judge-a
want_not "--check exits non-zero on drift" "reported clean while drifted" \
  run "$d" --check

before="$(md5 -q "$d/CLAUDE.md")"
run "$d" --check
want "--check never writes" "file was modified" \
  same_bytes "$d/CLAUDE.md" "$before"

run "$d"
want "--check exits zero once reconciled" "still reporting drift" \
  run "$d" --check
rm -rf "$d"

echo
echo "== tracked source =="

want "the tracked block still defines L1-L7" "rule headings missing" \
  rg -qN '^### L[1-7]\.' "$BLOCK"

# A gentle-ai marker in this file would hand the block back to `gentle-ai sync`,
# which is the one thing the whole mechanism exists to avoid.
want_not "the tracked block carries no gentle-ai marker" "a marker would make gentle-ai own it" \
  rg -qN '<!-- /?gentle-ai:' "$BLOCK"

echo
if [ $fail -eq 0 ]; then
  echo "All override tests pass."
else
  echo "Some override tests failed."
fi
exit $fail
