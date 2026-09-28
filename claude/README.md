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
| `settings.fragment.json` | The `hooks`, `statusLine` and `subagentPromptCacheTtl` keys merged into `~/.claude/settings.json` |
| `test-hooks.sh` | 35 golden inputs, both directions |
| `gentle-ai-overrides/` | Local SDD rules that outrank gentle-ai's own, and the reconciler that keeps them alive |
| `workflows/` | Scripts for the `Workflow` tool, symlinked into `~/.claude/workflows/` |
| `test-overrides.sh` | 22 golden inputs for the reconciler, run against a throwaway `CLAUDE_DIR` |

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
`skills/`, `agents/`, `commands/`, `output-styles/`, and the marked regions of
the global `CLAUDE.md` — is generated and owned by `gentle-ai sync`. Tracking
it here would vendor a package manager's output and fight the next sync. The
Brewfile declares `gentleman-programming/tap/gentle-ai`; the tool owns its own
files.

The exception is [`gentle-ai-overrides/`](#gentle-ai-overrides), which tracks
only what gentle-ai provably does not own: the region of `CLAUDE.md` past its
last marker, plus one frontmatter key the reconciler re-applies after each
sync. Nothing generated is copied into this repo.

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

## gentle-ai-overrides/

`gentle-ai` owns `~/.claude/skills/`, `~/.claude/agents/` and most of
`~/.claude/CLAUDE.md`. This directory is the one seam where local rules can
outrank it without forking the tool.

### Why it can work at all

`gentle-ai sync` rewrites `CLAUDE.md` through
`filemerge.InjectMarkdownSection`, which rebuilds the file as
`before + block + after` for one `<!-- gentle-ai:NAME -->` region at a time.
Anything outside every marker is never touched. So `CLAUDE.local-overrides.md`
is appended past the last marker under its own
`<!-- dotfiles:local-sdd-overrides -->` sentinels, and survives on its own.

Agent definitions get no such courtesy: every file in gentle-ai's embed is
overwritten wholesale on each install (`WriteFileAtomic`, no merge). The
`memory: project` key on the reviewer agents therefore has to be re-applied,
which is the reconciler's second job.

### The rules

`CLAUDE.local-overrides.md` carries L1–L7. They come from measuring 10 archived
SDD changes in `reels-lab`, where the pipeline found zero implementation
defects by code review: every FAIL was a missing test, and the one change that
needed six remediation rounds was a single requirement that never enumerated
its entry points. The rules push work upstream — test tasks per scenario,
entry points per validation requirement — instead of paying for it in
verification rounds. The raw table is in the knowledge vault under
`03_Resources/Tech/IA Engineering/`.

### Keeping them alive

```bash
gentle-ai-overrides/reconcile.sh           # apply, print what changed
gentle-ai-overrides/reconcile.sh --quiet   # apply, print only on change
gentle-ai-overrides/reconcile.sh --check   # report drift, exit 1, change nothing
```

Three things run it, so it should never need running by hand:

- `scripts/claude.sh`, on install.
- The `gentle-ai` wrapper in `zsh/functions.zsh`, after `install`, `sync` and
  `upgrade` — the only commands that cause drift. It forwards every argument
  and preserves the exit code.
- `--check` in CI or a pre-commit hook, if drift should ever fail a build.

It refuses to touch a `CLAUDE.md` whose gentle-ai markers are unbalanced: that
means a sync was interrupted, and splicing into a half-written file would put
the block inside a region about to be rewritten.

## workflows/

`~/.claude/workflows/` holds scripts for the `Workflow` tool, which runs a DAG
of agents deterministically instead of leaving the orchestration to the model.
gentle-ai never writes there, so these are plain symlinks.

`sdd-chain.js` encodes the SDD pipeline: exploration fanned out across three
scoped readers, spec and design in parallel (neither depends on the other —
both read only the proposal), a task schema that forces every work unit to
declare the files it writes, apply and verify pipelined per unit, and archive
only at zero CRITICALs. It proves the file partition before running writers in
parallel and degrades any overlapping units back to serial. Its verify schema
requires each CRITICAL to be classified `coverage`, `spec_ambiguity` or
`implementation`, which is what keeps the measurement behind L1-L7 current
instead of a one-off.

Running a workflow needs explicit opt-in per invocation; installing the script
does not run anything.
