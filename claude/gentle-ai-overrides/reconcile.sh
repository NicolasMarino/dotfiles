#!/usr/bin/env bash

# Reconciles the local SDD overrides against whatever gentle-ai last installed.
#
# WHY THIS EXISTS
#   `gentle-ai install|sync|upgrade` rewrites everything it ships. Two different
#   durability rules apply, and the split is why this script has two jobs:
#
#   * ~/.claude/CLAUDE.md — gentle-ai only replaces the regions between its own
#     `<!-- gentle-ai:NAME -->` / `<!-- /gentle-ai:NAME -->` markers
#     (internal/components/filemerge/section.go :: InjectMarkdownSection rebuilds
#     the file as before + block + after). Anything outside every marker survives,
#     so the overrides block is appended at EOF under its own sentinels.
#
#   * ~/.claude/agents/*.md — every file that ships in gentle-ai's embed is
#     overwritten wholesale on each install (WriteFileAtomic per file, no merge).
#     The reviewer agents therefore need `memory: project` re-applied every time.
#
# MODES
#   reconcile.sh            apply, printing what changed
#   reconcile.sh --quiet    apply, printing only on change or error
#   reconcile.sh --check    report drift and exit 1; change nothing

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BLOCK_SRC="$SCRIPT_DIR/CLAUDE.local-overrides.md"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
AGENTS_DIR="$CLAUDE_DIR/agents"

OPEN='<!-- dotfiles:local-sdd-overrides -->'
CLOSE='<!-- /dotfiles:local-sdd-overrides -->'

# Reviewer agents that benefit from cross-session project memory. Judges stay
# blind to *each other* — separate memory dirs — never to the codebase history.
REVIEWERS=(
  jd-judge-a
  jd-judge-b
  review-risk
  review-readability
  review-reliability
  review-resilience
)

MODE=apply
case "${1:-}" in
  --check) MODE=check ;;
  --quiet) MODE=quiet ;;
  '') ;;
  *) printf 'usage: reconcile.sh [--check|--quiet]\n' >&2; exit 2 ;;
esac

changed=0
drift=()

say() { [ "$MODE" = quiet ] || printf '%s\n' "$1"; }
note() { printf '%s\n' "$1"; }

[ -f "$BLOCK_SRC" ] || { note "reconcile: missing $BLOCK_SRC"; exit 1; }

# --------------------------------------------------------------------------
# 1. CLAUDE.md overrides block
# --------------------------------------------------------------------------

if [ ! -f "$CLAUDE_MD" ]; then
  say "reconcile: no $CLAUDE_MD yet — skipping the overrides block"
else
  desired="$OPEN
$(cat "$BLOCK_SRC")
$CLOSE"

  current=""
  if rg -qNF "$OPEN" "$CLAUDE_MD"; then
    current="$(awk -v o="$OPEN" -v c="$CLOSE" '
      $0 == o { inside = 1 }
      inside  { print }
      $0 == c { inside = 0 }
    ' "$CLAUDE_MD")"
  fi

  if [ "$current" = "$desired" ]; then
    say "ok        CLAUDE.md overrides block up to date"
  elif [ "$MODE" = check ]; then
    drift+=("CLAUDE.md overrides block ${current:+stale}${current:-absent}")
  else
    # Refuse to splice into a file whose gentle-ai markers are unbalanced —
    # that means a sync was interrupted, and appending would land inside a
    # half-written region.
    opens=$(rg -cN '^<!-- gentle-ai:[a-z-]+ -->$' "$CLAUDE_MD" || true)
    closes=$(rg -cN '^<!-- /gentle-ai:[a-z-]+ -->$' "$CLAUDE_MD" || true)
    if [ "${opens:-0}" != "${closes:-0}" ]; then
      note "reconcile: ERROR — $CLAUDE_MD has ${opens:-0} gentle-ai open markers and ${closes:-0} close markers."
      note "           Refusing to edit a file mid-sync. Re-run 'gentle-ai sync', then this script."
      exit 1
    fi

    tmp="$CLAUDE_MD.reconcile.tmp"
    if [ -n "$current" ]; then
      # Replace in place, keeping the block wherever it already sits.
      #
      # Split into head/tail and reassemble rather than substituting inside awk:
      # BSD awk rejects a multi-line string passed through -v ("newline in
      # string"), so the block can never travel as an awk variable.
      awk -v o="$OPEN" '$0 == o { exit } { print }' "$CLAUDE_MD" > "$tmp"
      printf '%s\n' "$desired" >> "$tmp"
      awk -v c="$CLOSE" 'seen { print } $0 == c { seen = 1 }' "$CLAUDE_MD" >> "$tmp"
    else
      # First install: append at EOF, which is outside every gentle-ai region.
      { cat "$CLAUDE_MD"; printf '\n'; printf '%s\n' "$desired"; } > "$tmp"
    fi

    # A splice that lost the gentle-ai markers means the awk went wrong.
    newopens=$(rg -cN '^<!-- gentle-ai:[a-z-]+ -->$' "$tmp" || true)
    if [ "${newopens:-0}" != "${opens:-0}" ]; then
      rm -f "$tmp"
      note "reconcile: ERROR — splice would have dropped gentle-ai markers. Left $CLAUDE_MD untouched."
      exit 1
    fi

    command mv -f "$tmp" "$CLAUDE_MD"
    say "patched   CLAUDE.md overrides block"
    changed=1
  fi
fi

# --------------------------------------------------------------------------
# 2. `memory: project` on the reviewer agents
# --------------------------------------------------------------------------

for name in "${REVIEWERS[@]}"; do
  file="$AGENTS_DIR/$name.md"

  if [ ! -f "$file" ]; then
    say "skipped   $name (not installed)"
    continue
  fi

  if rg -qN '^memory:' "$file"; then
    say "ok        $name (memory already set)"
    continue
  fi

  if [ "$MODE" = check ]; then
    drift+=("$name is missing 'memory: project'")
    continue
  fi

  # Insert before the closing `---` of the YAML frontmatter, i.e. the second
  # line that is exactly `---`.
  awk '
    BEGIN { fence = 0; done = 0 }
    /^---[[:space:]]*$/ {
      fence++
      if (fence == 2 && !done) { print "memory: project"; done = 1 }
      print; next
    }
    { print }
  ' "$file" > "$file.tmp"

  # Refuse a result that lost the frontmatter or failed to grow by exactly the
  # inserted line.
  if ! head -1 "$file.tmp" | rg -qN '^---[[:space:]]*$' \
     || ! rg -qN '^memory: project$' "$file.tmp" \
     || [ "$(wc -l < "$file.tmp")" -ne "$(( $(wc -l < "$file") + 1 ))" ]; then
    rm -f "$file.tmp"
    note "reconcile: WARNING — patch for $name produced an unexpected result; left untouched"
    continue
  fi

  command mv -f "$file.tmp" "$file"
  say "patched   $name (memory: project)"
  changed=1
done

# --------------------------------------------------------------------------
# Result
# --------------------------------------------------------------------------

if [ "$MODE" = check ]; then
  if [ ${#drift[@]} -eq 0 ]; then
    printf 'reconcile: no drift\n'
    exit 0
  fi
  printf 'reconcile: %d item(s) drifted\n' "${#drift[@]}"
  printf '  - %s\n' "${drift[@]}"
  printf "run 'dotfiles/claude/gentle-ai-overrides/reconcile.sh' to restore\n"
  exit 1
fi

if [ "$changed" = 1 ]; then
  note "reconcile: local SDD overrides restored"
else
  say "reconcile: nothing to do"
fi
