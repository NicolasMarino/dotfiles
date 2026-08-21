#!/bin/bash
# PreToolUse guard for Bash tool calls. Three independent checks:
#   1. no AI attribution in commit messages
#   2. destructive commands
#   3. modern CLI preference (rg/bat/fd/eza)
# A denial is JSON on stdout with permissionDecision "deny" and exit 0.
# Every reason names the exact replacement: a vague denial causes retry loops.

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -z "$cmd" ] && exit 0

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

# --- 1. commit attribution ---------------------------------------------
# Scoped to `git commit`. PR and issue bodies are allowed to carry the trailer.
if grep -qE '(^|[[:space:];&|])git[[:space:]]+commit' <<<"$cmd" \
   && grep -qiE 'co-authored-by|generated with .{0,3}claude|🤖' <<<"$cmd"; then
  deny "This user never puts AI attribution in commit messages. Remove the Co-Authored-By trailer and any 'Generated with Claude' line, then commit again with the conventional-commit subject and body only."
fi

# --- 2. destructive commands -------------------------------------------
rm_recursive='rm[[:space:]]+([^|;&]*[[:space:]])?-[[:alnum:]]*[rR]'
# The $HOME alternatives below are regex source, not variables to expand.
# shellcheck disable=SC2016
rm_wide_target='rm[[:space:]]+((-{1,2}[^[:space:]]+)[[:space:]]+)*(/|/\*|~|~/|~/\*|\*|\.|\.\.|\./\*|\$HOME|\$HOME/|\$HOME/\*)([[:space:]]|$|[;&|])'
if grep -qE "$rm_recursive" <<<"$cmd" && grep -qE "$rm_wide_target" <<<"$cmd"; then
  deny "Recursive rm against a root, home, or wildcard target is blocked. Name the concrete directory you mean (for example 'rm -rf ./build'), or ask the user to run it themselves with '! <command>'."
fi

if grep -qE 'git[[:space:]]+push[^|;&]*--force([^-]|$)' <<<"$cmd"; then
  deny "Plain 'git push --force' overwrites whatever the remote gained since your last fetch. Use 'git push --force-with-lease' instead, which refuses when the remote moved."
fi

if grep -qE 'git[[:space:]]+reset[^|;&]*--hard' <<<"$cmd"; then
  deny "'git reset --hard' discards uncommitted work with no recovery path. Use 'git stash' to park the changes, or 'git restore <path>' to revert a specific file. If the reset really is what the user asked for, have them run it with '! <command>'."
fi

if grep -qiE '(drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+table)' <<<"$cmd"; then
  deny "DROP / TRUNCATE against a live database is blocked here. Write it as a reviewed migration file instead, or ask the user to run it themselves with '! <command>'."
fi

# --- 3. modern CLI preference ------------------------------------------
# Heredocs are skipped whole: `cat > f <<EOF` is a legitimate write, and the
# body it carries can mention any of these tools without invoking them.
if ! grep -q '<<' <<<"$cmd"; then
  norm=${cmd//&&/$'\n'}
  norm=${norm//||/$'\n'}
  norm=${norm//|/$'\n'}
  norm=${norm//;/$'\n'}
  while IFS= read -r segment; do
    read -r first _ <<<"$segment"
    case "$first" in
      sudo|env|time|nice) read -r _ first _ <<<"$segment" ;;
    esac
    case "$first" in
      grep) deny "Use 'rg' instead of 'grep'. Same query, and it respects .gitignore by default. For a literal string add -F, for case-insensitive -i." ;;
      cat)  deny "Use 'bat --plain' instead of 'cat' to read a file (add --line-range A:B for a slice). Writing a file with 'cat > f <<EOF' is fine and is not blocked." ;;
      find) deny "Use 'fd' instead of 'find'. 'fd <pattern>' replaces 'find . -name \"*pattern*\"', and 'fd -e ts' filters by extension." ;;
      ls)   deny "Use 'eza' instead of 'ls' (-a for hidden files, -l for long form, --tree for a tree)." ;;
    esac
  done <<<"$norm"
fi

exit 0
