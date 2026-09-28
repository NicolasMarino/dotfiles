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
| `statusline.sh` | Status line: model, branch, cost, context vs token budget, compactions, rate-limit pace |
| `settings.fragment.json` | The `hooks`, `statusLine` and `attribution` blocks merged into `~/.claude/settings.json` |
| `test-hooks.sh` | 54 golden inputs, both directions, plus the on-disk body-file branch |
| `test-statusline.sh` | Golden inputs for the status line (ANSI stripped), synthetic transcripts and git repo |

## bash-guard.sh

Three checks in one process, ~30ms per call. `PreToolUse` on `Bash` runs on
every shell command the agent issues, so it has to stay well under the ~100ms
budget where latency starts being felt.

1. **AI attribution.** Denies any publishing command — `git commit`,
   `git tag`, and `gh pr|release|issue` followed by a writing subcommand
   (`create`, `edit`, `comment`, `merge`, …) — carrying `Co-Authored-By`,
   `Generated with Claude`, a `claude.ai/code/session_` URL, or 🤖. Body text
   passed as a file (`--body-file`, `--notes-file`) is opened and scanned too,
   because `gh` reads bodies from disk as often as from the command line.

   This was once scoped to `git commit` on purpose, on the reading that the
   rule said "commits". A session URL then went out on three pull requests of
   a public repository. The rule was never about the word: it is about anything
   that leaves this machine carrying the user's name. Non-publishing commands
   are untouched, and reading verbs are matched by subcommand rather than by
   noun, so a plain search over the tree and `gh pr view … | rg` both still
   run. A guard that blocks the hunt for a leak is worse than no guard — the
   first draft matched `gh pr` whole and denied exactly that.

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

## Status line

```
Opus · dotfiles · ⎇ main · $1.23 · +156/-23 · api 2m
ctx 84k/250k ███░░░░░░░ 33% · ⟲2 · 5h 60% ◆40% (3h00m) · 7d 20% ◇50% · → ~40% by reset
```

Context is measured against a personal **token budget**, not the model window:
`input + cache_creation + cache_read` from `context_window.current_usage` (the
same input-only sum Claude Code uses for `used_percentage`). Green under 60%,
yellow under 80%, red with a `/compact` hint from 80%. When `current_usage` is
null (before the first call, right after `/compact`) it falls back to the
model-window percentage.

| Env var | Default | Meaning |
| ------- | ------- | ------- |
| `CLAUDE_CTX_BUDGET` | `250000` | Token budget for the status line |

- **Pace**: `◆40%` means more of the 5h/7d window is used than the 40% of it
  that has elapsed; `◇` means under pace.
- **`⟲N`**: compactions this session, `rg -c` on the transcript for
  `"subtype":"compact_boundary"`. Dim at 1, yellow at 2, red from 3.
- **Git**: the git dir is resolved once per session; the branch is re-read with
  `git --no-optional-locks` only when the content of `HEAD` changes.

Everything is one `jq` call per render plus, at most, an `rg -c` on the
transcript. No network.

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
