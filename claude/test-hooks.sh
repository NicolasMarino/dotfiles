#!/bin/bash
# Payloads are deliberately literal (unexpanded $HOME, quote-split key
# fragments) and the runners are invoked indirectly through "$2" in expect().
# SC2317 and SC2329 are the same "unreachable function" finding, renumbered
# between versions; pre-commit pins an older one than Homebrew ships.
# shellcheck disable=SC2016,SC2026,SC2317,SC2329

# Golden-input tests for the two global PreToolUse guards.
# Secret payloads are assembled from fragments at runtime so this file itself
# does not trip write-guard when it is written or edited.
# Test the tracked sources, not the installed symlinks: CI has no ~/.claude,
# and claude.sh links these exact files, so the two are the same bytes.
HOOKS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/hooks"
G="$HOOKS_DIR/bash-guard.sh"
W="$HOOKS_DIR/write-guard.sh"
fail=0

run_bash() { jq -n --arg c "$1" '{tool_input:{command:$c}}' | "$G"; }
run_write() { jq -n --arg c "$1" '{tool_input:{content:$c}}' | "$W"; }

expect() { # expect <deny|allow> <runner> <payload> [label]
  out=$("$2" "$3")
  if [ -n "$out" ]; then got=deny; else got=allow; fi
  label=${4:-$3}
  if [ "$got" != "$1" ]; then
    printf 'FAIL  want=%-5s got=%-5s :: %s\n' "$1" "$got" "$label"
    fail=1
  else
    printf 'ok    %-5s :: %s\n' "$got" "$label"
  fi
}

echo "== bash-guard: should DENY =="
expect deny run_bash 'git commit -m "feat: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"'
expect deny run_bash 'git commit -m "fix: y

🤖 Generated with Claude Code"'
expect deny run_bash 'gh pr create --title x --body "done

\U0001F916 Generated with Claude Code"' 'PR body: generated-with footer'
expect deny run_bash 'gh pr create --title x --body "see https://claude.ai/code/session_017Bv"' 'PR body: session URL'
expect deny run_bash 'gh pr comment 3 --body "Co-Authored-By: Claude"' 'PR comment: trailer'
expect deny run_bash 'gh release create v1.0.0 --notes "ships. https://claude.ai/code/session_017Bv"' 'release notes: session URL'
expect deny run_bash 'gh issue create --title x --body "Co-Authored-By: Claude"' 'issue body: trailer'
expect deny run_bash 'git tag -a v1 -m "Co-Authored-By: Claude"' 'tag message: trailer'
expect deny run_bash 'rm -rf ~'
expect deny run_bash 'rm -rf /'
expect deny run_bash 'rm -rf $HOME/'
expect deny run_bash 'rm -rf *'
expect deny run_bash 'sudo rm -rf /'
expect deny run_bash 'git push --force'
expect deny run_bash 'git push origin main --force'
expect deny run_bash 'git reset --hard origin/main'
expect deny run_bash 'psql -c "DROP TABLE users"'
expect deny run_bash 'grep -r foo .'
expect deny run_bash 'bat f.ts | grep foo'
expect deny run_bash 'cat src/index.ts'
expect deny run_bash 'find . -name "*.ts"'
expect deny run_bash 'ls -la'

echo
echo "== bash-guard: should ALLOW =="
expect allow run_bash 'git commit -m "feat(hooks): add global guards"'
expect allow run_bash 'gh pr create --title x --body "a clean description"' 'PR body: nothing to hide'
expect allow run_bash 'gh release view v1.0.0 --json body' 'reading a release is not publishing'
expect allow run_bash 'gh pr view 5 --json body | rg -c "co-authored-by"' 'auditing a PR for the trailer is a read'
expect allow run_bash 'gh pr list --json title' 'listing PRs is a read'
expect allow run_bash 'gh pr diff 5' 'diffing a PR is a read'
expect allow run_bash 'rg -n "claude.ai/code/session_" README.md' 'hunting for the leak is not the leak'
expect allow run_bash 'rg -c "co-authored-by" *.md' 'auditing for the trailer stays allowed'
expect allow run_bash 'rm -rf ./build'
expect allow run_bash 'rm -rf node_modules'
expect allow run_bash 'rm -f tmp.log'
expect allow run_bash 'git push --force-with-lease'
expect allow run_bash 'rg -n useTaskStore src/'
expect allow run_bash 'bat --plain package.json'
expect allow run_bash 'fd -e ts src'
expect allow run_bash 'eza -a src'
expect allow run_bash 'git log --grep=fix --oneline'
expect allow run_bash 'npm test -- --watch'
expect allow run_bash 'echo "the cat sat" > note.txt'
expect allow run_bash 'go test ./... | tail -20'
expect allow run_bash "cat > f.sh <<'EOF'
grep foo bar
ls -la
EOF" 'heredoc write whose body mentions grep/ls'

echo
echo "== bash-guard: body files on disk =="
# The case that actually leaked. `gh` reads bodies from disk as often as from
# the command line, so a payload-only test can never reach this branch.
bodydir=$(mktemp -d)
trap 'rm -rf "$bodydir"' EXIT
printf 'a normal description\n\nhttps://claude.ai/code/session_017Bv\n' > "$bodydir/dirty.md"
printf 'a normal description, nothing else\n' > "$bodydir/clean.md"
expect deny run_bash "gh pr create --title x --body-file $bodydir/dirty.md" 'body file: session URL on disk'
expect deny run_bash "gh release create v1 --notes-file $bodydir/dirty.md" 'notes file: session URL on disk'
expect allow run_bash "gh pr create --title x --body-file $bodydir/clean.md" 'body file: clean'

echo
echo "== write-guard: should DENY =="
expect deny run_write 'const key = "'AKIA'IOSFODNN7EXAMPLE"' 'aws access key id'
expect deny run_write 'OPENAI_KEY='sk-'proj-abcdefghijklmnopqrstuvwxyz012345' 'openai-style key'
expect deny run_write 'token: '"ghp_"'abcdefghijklmnopqrstuvwxyz0123456789' 'github pat'
expect deny run_write '-----BEGIN RSA '"PRIVATE"' KEY-----
MIIEow==' 'private key block'

echo
echo "== write-guard: should ALLOW =="
expect allow run_write 'const key = process.env.OPENAI_API_KEY' 'env var read'
expect allow run_write 'API_KEY=REPLACE_ME' 'obvious placeholder'
expect allow run_write 'const skater = "sk-8"' 'short sk- lookalike'
expect allow run_write "$(<"$W")" 'write-guard scanning its own source'

echo
if [ $fail -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit $fail
