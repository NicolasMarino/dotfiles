# Claude Code config

Hooks are shell commands the Claude Code harness runs at fixed points in its
tool-call lifecycle. They are not prompts: no model is involved, they always
run, and a `PreToolUse` hook can veto the tool call outright. That is the whole
point of these three — every rule here also exists in prose in `~/.claude/CLAUDE.md`,
where it depends on the agent remembering it. Here it is enforced.

Installed by `scripts/claude.sh`, which is called from `install.sh`.

## What is here

| File | Purpose |
| ---- | ------- |
| `hooks/bash-guard.sh` | `PreToolUse` on `Bash` — commit attribution, destructive commands, CLI preference |
| `hooks/write-guard.sh` | `PreToolUse` on `Edit\|Write\|MultiEdit` — credential scan |
| `statusline.sh` | Status line: model, branch, session cost, context and rate-limit budget |
| `settings.fragment.json` | The `hooks` and `statusLine` blocks merged into `~/.claude/settings.json` |
| `test-hooks.sh` | 35 golden inputs, both directions |

## bash-guard.sh

Three checks in one process, ~30ms per call. `PreToolUse` on `Bash` runs on
every shell command the agent issues, so it has to stay well under the ~100ms
budget where latency starts being felt.

1. **Commit attribution.** Denies `git commit` whose message carries
   `Co-Authored-By`, `Generated with Claude`, or 🤖. Scoped to `git commit` on
   purpose: `gh pr create --body` is allowed to carry the trailer.

2. **Destructive commands.** Denies recursive `rm` against root, home, or a
   bare wildcard; `git push --force` without `--force-with-lease`;
   `git reset --hard`; and `DROP`/`TRUNCATE TABLE`. Scoped deletes like
   `rm -rf ./build` and `rm -rf node_modules` still pass — blocking every
   `rm -rf` would be noise, and a guard that cries wolf gets uninstalled.

3. **CLI preference.** Routes `grep`/`cat`/`find`/`ls` to `rg`/`bat`/`fd`/`eza`,
   matching the first token of each command position (start, `|`, `&&`, `;`)
   rather than anywhere in the string — so `git log --grep` and `rg 'a|b'` are
   untouched. **Any command containing `<<` skips this check entirely**: a
   heredoc is a legitimate write and its body can mention any of these tools
   without invoking them.

Every denial names the exact replacement. A bare "not allowed" sends the model
into a retry loop; `"use rg instead of grep, add -F for a literal string"`
does not.

## write-guard.sh

Scans the content of every `Write`, `Edit`, and `MultiEdit` for seven
credential shapes (OpenAI, AWS, GitHub classic and fine-grained, Slack, Google,
PEM private key blocks) and blocks the write.

The regexes are written so that **none of them matches its own literal text**
— `AKIA[0-9A-Z]{16}` requires 16 uppercase alphanumerics after `AKIA`, and the
next character in the pattern source is `[`. That is what lets this script edit
itself without tripping its own scan, and the same trick keeps `test-hooks.sh`
readable: its payloads are assembled from concatenated fragments at runtime, so
no key-shaped string sits on disk for gitleaks to flag.

`grep -qE -e "$pattern"` is not decoration. Without `-e`, the PEM pattern
starts with `-` and `grep` reads it as an option, exits non-zero, and the check
passes everything — silently.

## What is deliberately NOT here

Everything under `~/.claude` carrying a `<!-- gentle-ai:... -->` marker —
`skills/`, `agents/`, `commands/`, `output-styles/`, and the global
`CLAUDE.md` — is generated and owned by `gentle-ai sync`. Tracking it here
would vendor a package manager's output and fight the next sync. The Brewfile
declares `gentleman-programming/tap/gentle-ai`; the tool owns its own files.

Session state (`projects/`, `sessions/`, `history.jsonl`, `security/`) is
neither config nor portable.

## Why `settings.json` is not in this repo

Only the fragment is tracked. The full `~/.claude/settings.json` also
holds telemetry endpoints, plugin and marketplace state, and an `autoMode`
environment section describing deploy targets, CI secret names, internal
service hostnames, and where local secret material lives on disk. None of that
is a credential, but together it is an infrastructure map, and this repository
is public.

`scripts/claude.sh` merges the tracked fragment into whatever settings.json
already exists: `hooks` merges per event, so unrelated events survive, and
every other fragment key replaces wholesale. Keys the fragment never mentions
are left alone. It backs up to a timestamped `settings.json.<ts>.bak` first.

## Adding a hook

Put the logic in a script here, add the entry to `settings.fragment.json`, and add
golden inputs for both directions to `test-hooks.sh` — the allow cases matter
more than the deny ones. A guard that stops matching still exits 0, so nothing
tells you it broke except a test.

`scripts/claude.sh` runs the suite on install and fails the install if it does
not pass.

## Turning one off

Remove its entry from `settings.fragment.json` and rerun `scripts/claude.sh`, or
edit `~/.claude/settings.json` directly for a one-machine change. Hooks reload
mid-session, so the change takes effect on the next tool call.
