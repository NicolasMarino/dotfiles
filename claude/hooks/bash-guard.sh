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

# --- 1. AI attribution -------------------------------------------------
# Every publishing verb, not just `git commit`. This was scoped to commits on
# purpose once, on the reading that the rule said "commits" — and a session URL
# went out on three pull requests of a public repository. The rule was never
# about the word: it is about anything that leaves this machine carrying the
# user's name. A claude.ai session link is not a credential, but it is a private
# identifier, and publishing it is not the agent's call.
#
# Only publishing verbs are inspected, so searching for these strings still
# works. A guard that blocks the hunt for a leak is worse than no guard.
attribution='co-authored-by|generated with .{0,3}claude|claude\.ai/code/session_|🤖'
publishing='(^|[[:space:];&|])(git[[:space:]]+(commit|tag)|gh[[:space:]]+(pr|release|issue))'

if grep -qE "$publishing" <<<"$cmd"; then
  if grep -qiE "$attribution" <<<"$cmd"; then
    deny "Nothing published from this machine carries AI attribution: not commits, PR bodies, comments, release notes or issues. Remove the Co-Authored-By trailer, any 'Generated with Claude' line, and any claude.ai session URL, then run it again."
  fi

  # `gh` reads bodies from disk as often as from the command line, and a footer
  # sitting in that file is invisible to every check on the command text. That
  # is exactly how one got published.
  read -ra parts <<<"$cmd"
  for i in "${!parts[@]}"; do
    case "${parts[$i]}" in
      --body-file|--notes-file|--file|-F) bodyfile="${parts[$((i + 1))]}" ;;
      --body-file=*|--notes-file=*|--file=*) bodyfile="${parts[$i]#*=}" ;;
      *) continue ;;
    esac
    bodyfile="${bodyfile%\"}"; bodyfile="${bodyfile#\"}"
    bodyfile="${bodyfile%\'}"; bodyfile="${bodyfile#\'}"
    [ -f "$bodyfile" ] || continue
    if grep -qiE "$attribution" "$bodyfile"; then
      deny "The body file '$bodyfile' carries AI attribution. Nothing published from this machine does: not commits, PR bodies, comments, release notes or issues. Strip it from the file and run the command again."
    fi
  done
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
