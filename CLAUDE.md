# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal dotfiles repo for macOS (primary) and Windows (WIP). There is no build, no test suite, and no application code — it is Bash orchestration + config files delivered to `$HOME` via symlinks. "Running" it means running the installer.

## Commands

```bash
./install.sh                              # Full setup — idempotent, safe to re-run
bash scripts/symlink.sh                   # Re-link zsh + git configs only
bash scripts/install_tools.sh             # Oh My Zsh, plugins, fnm/Node LTS, fzf keybindings
bash scripts/vscode.sh                    # Link VS Code settings + install extensions
bash scripts/macos.sh                     # Apply macOS defaults (prompts inside install.sh)
brew bundle --file=brew/Brewfile          # Sync packages after editing the Brewfile

pre-commit install                        # One-time: activate gitleaks + shellcheck hooks
pre-commit run --all-files                # Lint everything before committing
pre-commit run shellcheck --all-files     # Lint just the shell scripts

source ~/.zshrc                           # or the `reload` alias — apply shell changes
```

`install.sh` runs the phases in a fixed order — backup → symlink → tools → `brew bundle` → macOS defaults → VS Code — and ends with `exec zsh`. Each phase script is standalone and re-runnable, so prefer running the single relevant script over the whole installer while iterating.

## Architecture

### The repo path is load-bearing

The repo **must** live at `~/Documents/git/personal/dotfiles`. Two consumers hardcode it and are not derived from `$DOTFILES_DIR`:

- `zsh/.zshrc` sources `$HOME/Documents/git/personal/dotfiles/zsh/{aliases,functions}.zsh`
- `git/.gitconfig` `includeIf` and `include` blocks point at `~/Documents/git/personal/dotfiles/git/.gitconfig.{personal,work,local}`

The install scripts themselves resolve `DOTFILES_DIR` correctly from `BASH_SOURCE`, which makes the breakage silent: the installer will happily symlink from a clone at any path, and then the shell/git configs point somewhere that doesn't exist. If you change the repo location, both files above must change too.

### Two symlink layers, one backup list

`scripts/symlink.sh` links only `.zshrc`, `.gitconfig`, `.gitignore_global`. VS Code's `settings.json` is linked separately by `scripts/vscode.sh` (into `~/Library/Application Support/Code/User/`) because it needs the `code` CLI on PATH and bails out cleanly when it isn't.

`scripts/backup.sh` has its own `FILES_TO_BACKUP` array. **Adding a symlink to `symlink.sh` without adding the same path to `backup.sh` means overwriting a user's real config with no backup.** Keep them in sync. Backups land in `~/.dotfiles_backup/` timestamped; existing symlinks are removed rather than backed up.

### Shared script conventions

Every script under `scripts/` (and `install.sh`) opens the same way:

```bash
set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"
```

`scripts/common.sh` is the only shared module — it exports `print_header`, `print_success`, `print_error`, `print_warning`, `print_info`. Use those instead of raw `echo` so output stays consistent. New scripts follow the same header verbatim.

Idempotency is a hard requirement, not a nicety: guard every install with `command -v` / `[ ! -d ]` / `[ ! -f ]` checks, as the existing scripts do.

### Machine-local escape hatches (all gitignored)

Never commit these, and never inline machine-specific values into the tracked files instead:

| File | Purpose |
| --- | --- |
| `~/.zshrc.local` | Per-machine shell config, sourced near the end of `.zshrc` |
| `git/.gitconfig.personal` | Personal identity/signing key — copy from `.sample` |
| `git/.gitconfig.work` | Work identity/signing key — copy from `.sample` |
| `git/.gitconfig.local` | Other machine-specific git overrides — loaded last by `.gitconfig`, so it wins over the personal/work includes |

When changing the shape of a conditional git config, update the corresponding `.sample` file — it's the only tracked record of the expected keys.

### Conditional git identity

`git/.gitconfig` uses `includeIf "gitdir:"` where **order matters**: `~/Documents/git/` loads work, then `~/Documents/git/personal/` overrides it for personal repos. A new scope must be appended after the broader one to win, and the unconditional `.gitconfig.local` include goes last of all.

### Package declaration is split

`brew/Brewfile` declares taps, formulae, casks **and** `vscode "..."` extensions. `vscode/extensions.txt` declares extensions again for `scripts/vscode.sh`, which installs them via `code --install-extension`. These two lists are independent and drift apart — when adding an extension, decide which mechanism owns it, or update both.

### Windows

`windows/install.ps1` is a parallel, self-contained implementation: it symlinks the PowerShell profile and reuses the **same** `git/.gitconfig` and `git/.gitignore_global` from this repo. Shell config is not shared. A change to `git/` affects both platforms; a change to `zsh/` does not.

## Pre-commit gates

`.pre-commit-config.yaml` runs:

- **gitleaks** — secret scanning. This repo tracks git configs and shell rc files, so a leaked token is a live risk; never work around a gitleaks failure.
- **shellcheck** — with `--exclude=SC1091,SC2088` and `exclude: '\.zsh(rc)?$'`. Zsh files are deliberately unlinted because ShellCheck can't parse zsh. That means `zsh/.zshrc`, `zsh/aliases.zsh`, and `zsh/functions.zsh` get **no** static checking — review them by hand and test with `source ~/.zshrc`.

`.editorconfig` governs indentation: 4 spaces for `*.{sh,zsh,bash}`, 2 for web/YAML. `.prettierrc` is a global export for other projects, not applied to this repo.

## Roadmap and docs

`ROADMAP.md` tracks phased work with checkboxes — update it when completing an item. `docs/GIT_CONFIG_GUIDE.md` documents the SSH (ed25519) and GPG commit-signing setup that the git configs assume.

## CI

`.github/workflows/ci.yml` runs three jobs on push and PR:

- **lint** — `pre-commit run --all-files`, the same pinned config as local, so CI and a dev machine cannot disagree about what passes.
- **guards** — `claude/test-hooks.sh`, golden-input tests for the two `PreToolUse` guards. They run against `claude/hooks/*.sh` directly (not the `~/.claude` symlinks) so they work on a runner with no install.
- **installer** — `bash -n` over every script, plus a check that every `scripts/*.sh` path `install.sh` invokes actually exists. That last one exists because adding a phase to `install.sh` while leaving the script untracked breaks a fresh clone under `set -e`.
