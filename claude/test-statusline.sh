#!/usr/bin/env bash
# Golden-input tests for statusline.sh and subagent-statusline.sh.
# Fixtures are inline; transcripts and git repos are synthetic and live in a
# throwaway dir. Assertions match substrings with ANSI colour codes stripped,
# plus a few colour checks on the raw output where colour is the behaviour.
# Requires jq, git, and rg (the compaction counter is skipped without rg).

CLAUDE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SL="$CLAUDE_DIR/statusline.sh"
SUB="$CLAUDE_DIR/subagent-statusline.sh"
fail=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
unset CLAUDE_CTX_BUDGET

NOW=$(date +%s)
ESC=$'\033'
RED="${ESC}[31m"
YELLOW="${ESC}[33m"
GREEN="${ESC}[32m"

strip() { sed -E "s/${ESC}\[[0-9;]*m//g"; }

# check <label> <haystack> <needle> [absent]
check() {
  if [ "$4" = "absent" ]; then
    case "$2" in *"$3"*) ok=0 ;; *) ok=1 ;; esac
  else
    case "$2" in *"$3"*) ok=1 ;; *) ok=0 ;; esac
  fi
  if [ $ok -eq 1 ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s :: %s %q in:\n%s\n' "$1" "${4:-want}" "$3" "$2"
    fail=1
  fi
}

render() { "$SL" | strip; }
render_raw() { "$SL"; }

echo "== statusline: missing fields =="
out=$(printf '{}' | render)
check 'empty input still renders a model' "$out" 'claude'
check 'empty input shows waiting line' "$out" 'waiting for first API response'
check 'no cost metrics when absent' "$out" 'api ' absent
check 'no lines changed when absent' "$out" '+0/-0' absent

out=$(printf '{"context_window":{"used_percentage":42,"current_usage":null}}' | render)
check 'null current_usage falls back to used_percentage' "$out" 'ctx ████░░░░░░ 42%'
check 'fallback shows no budget' "$out" '/250k' absent

echo
echo "== statusline: budget =="
budget_fixture() { # tokens split across the three input fields
  printf '{"context_window":{"used_percentage":5,"current_usage":{"input_tokens":%d,"output_tokens":999999,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d}}}' "$1" "$2" "$3"
}
out=$(budget_fixture 4000 10000 70000 | render)
check 'tokens = input + cache_creation + cache_read' "$out" 'ctx 84k/250k ███░░░░░░░ 33%'
check 'output tokens are not counted' "$out" '1.0M' absent
raw=$(budget_fixture 4000 10000 70000 | render_raw)
check 'under 60% of budget is green' "$raw" "${GREEN}ctx 84k"

raw=$(budget_fixture 0 0 170000 | render_raw)
check '60-79% of budget is yellow' "$raw" "${YELLOW}ctx 170k"
check 'no /compact hint below 80%' "$(printf '%s' "$raw" | strip)" '/compact' absent

raw=$(budget_fixture 0 0 200000 | render_raw)
check '80% of budget is red' "$raw" "${RED}ctx 200k"
check '/compact hint at 80%' "$(printf '%s' "$raw" | strip)" '/compact'

out=$(budget_fixture 0 0 300000 | render)
check 'over budget shows >100% with a full bar' "$out" '██████████ 120%'

out=$(budget_fixture 0 0 50000 | CLAUDE_CTX_BUDGET=100000 "$SL" | strip)
check 'CLAUDE_CTX_BUDGET overrides the default' "$out" 'ctx 50k/100k'
out=$(budget_fixture 0 0 50000 | CLAUDE_CTX_BUDGET=junk "$SL" | strip)
check 'invalid budget falls back to 250k' "$out" '/250k'

echo
echo "== statusline: session metrics =="
out=$(printf '{"cost":{"total_cost_usd":1.5,"total_lines_added":156,"total_lines_removed":23,"total_api_duration_ms":125000}}' | render)
check 'lines added/removed' "$out" '+156/-23'
check 'api time' "$out" 'api 2m'
out=$(printf '{"cost":{"total_lines_added":0,"total_lines_removed":0,"total_api_duration_ms":0}}' | render)
check 'zero metrics are hidden' "$out" '+0' absent

echo
echo "== statusline: pace markers =="
# 5h: 2h elapsed of 5h -> expected 40%. 7d: just under 3.5d elapsed -> expected 49%.
five_reset=$((NOW + 3 * 3600))
week_reset=$((NOW + 302400 + 30)) # +30s keeps the floor()s stable while the test runs
out=$(printf '{"rate_limits":{"five_hour":{"used_percentage":60,"resets_at":%d},"seven_day":{"used_percentage":20,"resets_at":%d}}}' "$five_reset" "$week_reset" | render)
check '5h over pace shows ◆expected' "$out" '5h 60% ◆40%'
check '7d under pace shows ◇expected' "$out" '7d 20% ◇49%'
check '7d linear forecast kept' "$out" '→ ~40% by reset'
out=$(printf '{"rate_limits":{"five_hour":{"used_percentage":10}}}' | render)
check 'no resets_at, no pace marker' "$out" '◆' absent
check 'no resets_at, still shows usage' "$out" '5h 10%'

echo
echo "== statusline: prompt cache is not shown =="
out=$(printf '{"prompt_cache":{"caching_observed":true,"warm":true,"expires_at":%d}}' $((NOW + 200)) | render)
check 'prompt_cache never renders a segment' "$out" 'cache' absent

echo
echo "== statusline: compactions =="
compact_line='{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto"}}'
quoted_line='{"type":"user","message":{"content":"the \"subtype\":\"compact_boundary\" marker"}}'
count_fixture() { # n real markers plus one escaped mention that must not count
  local f="$WORK/compact-$1.jsonl" i
  : >"$f"
  for ((i = 0; i < $1; i++)); do printf '%s\n' "$compact_line" >>"$f"; done
  printf '%s\n' "$quoted_line" >>"$f"
  printf '{"transcript_path":"%s"}' "$f"
}
if command -v rg >/dev/null 2>&1; then
  out=$(count_fixture 0 | render)
  check 'zero compactions hidden (escaped mention ignored)' "$out" '⟲' absent
  out=$(count_fixture 1 | render)
  check 'one compaction shown' "$out" '⟲1'
  raw=$(count_fixture 2 | render_raw)
  check 'two compactions are yellow' "$raw" "${YELLOW}⟲2"
  raw=$(count_fixture 3 | render_raw)
  check 'three compactions are red' "$raw" "${RED}⟲3"
else
  echo 'skip  compaction tests (rg not installed)'
fi

echo
echo "== statusline: git branch =="
repo="$WORK/repo"
git init -q -b main "$repo"
out=$(printf '{"session_id":"s1","workspace":{"current_dir":"%s"}}' "$repo" | render)
check 'branch shown' "$out" '⎇ main'
git -C "$repo" checkout -q -b feat/budget
out=$(printf '{"session_id":"s1","workspace":{"current_dir":"%s"}}' "$repo" | render)
check 'branch cache invalidated when HEAD changes' "$out" '⎇ feat/budget'
out=$(printf '{"session_id":"s1","workspace":{"current_dir":"%s"}}' "$WORK" | render)
check 'non-repo shows no branch' "$out" '⎇' absent

echo
echo "== subagent-statusline =="
sub_fixture='{"columns":60,"tasks":[
  {"id":"a1","name":"explorer","type":"Explore","tokenCount":84000,"description":"Map the statusline code"},
  {"id":"a2","name":"writer","tokenCount":210000,"description":"Implement the budget change across every file that needs it"},
  {"id":"a3","name":"runaway","tokenCount":300000},
  {"id":"a4","name":"pending"}
]}'
raw=$(printf '%s' "$sub_fixture" | "$SUB")
out=$(printf '%s' "$raw" | jq -r '"\(.id)=\(.content)"' | strip)
check 'one JSON line per task with tokens' "$(printf '%s\n' "$raw" | wc -l | tr -d ' ')" '3'
check 'tokens against budget' "$out" 'a1=explorer 84k/250k 33% · Map the statusline code'
check 'description truncated to columns' "$out" '…'
check 'past budget shows >100%' "$out" 'a3=runaway 300k/250k 120%'
check 'task without tokenCount keeps default row' "$out" 'a4=' absent
content() { printf '%s' "$raw" | jq -r --arg id "$1" 'select(.id == $id) | .content'; }
check 'under 60% is green' "$(content a1)" "${GREEN}84k"
check '80%+ is red' "$(content a2)" "${RED}210k"
check 'past budget is red' "$(content a3)" "${RED}300k"
out=$(printf '{"tasks":[{"id":"x","name":"n","tokenCount":50000}]}' | CLAUDE_CTX_BUDGET=100000 "$SUB" | jq -r .content | strip)
check 'subagent CLAUDE_CTX_BUDGET override' "$out" 'n 50k/100k 50%'
out=$(printf '{}' | "$SUB")
check 'no tasks, no output' "[$out]" '[]'

echo
if [ $fail -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit $fail
