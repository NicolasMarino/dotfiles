#!/bin/bash
# PreToolUse guard for Edit / Write / MultiEdit. Blocks credential material
# from reaching disk, where a later commit can carry it into history.
# Every pattern is written so it cannot match its own literal text in this
# file — editing this script does not trip the scan.

input=$(cat)
content=$(jq -r '
  [ .tool_input.content,
    .tool_input.new_string,
    (.tool_input.edits // [] | map(.new_string))
  ] | flatten | map(select(. != null)) | join("\n")
' <<<"$input")
[ -z "$content" ] && exit 0

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

check() {
  if grep -qE -e "$1" <<<"$content"; then
    deny "This write contains what looks like a live credential ($2). Read it from an environment variable at runtime and keep the value in a gitignored .env or the system keychain. If it is a placeholder, make that unmistakable — use a value like 'REPLACE_ME' rather than a realistic-looking key."
  fi
}

check 'sk-[A-Za-z0-9_-]{20,}'          'OpenAI-style API key'
check 'AKIA[0-9A-Z]{16}'               'AWS access key id'
check 'ghp_[A-Za-z0-9]{36}'            'GitHub personal access token'
check 'github_pat_[A-Za-z0-9_]{22,}'   'GitHub fine-grained token'
check 'xox[baprs]-[A-Za-z0-9-]{10,}'   'Slack token'
check 'AIza[0-9A-Za-z_-]{35}'          'Google API key'
check '-----BEGIN [A-Z ]*PRIVATE KEY-----' 'private key block'

exit 0
