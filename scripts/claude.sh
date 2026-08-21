#!/usr/bin/env bash

# Installs the hand-written Claude Code config: the PreToolUse guard hooks.
#
# ~/.claude/settings.json is deliberately NOT tracked in this repo: its
# autoMode.environment block records infrastructure details about private
# repositories (deploy hosts, CI secret names, where credentials live) and this
# repository is public. Only claude/settings.fragment.json is version
# controlled, and it is merged into whatever settings.json already exists.
#
# Everything under ~/.claude that carries a gentle-ai marker — skills/,
# agents/, commands/, output-styles/, CLAUDE.md — is owned by `gentle-ai sync`
# and must stay out of here. The Brewfile declares the tool; the tool owns its
# own output.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
FRAGMENT="$DOTFILES_DIR/claude/settings.fragment.json"

if ! command -v claude &> /dev/null; then
    print_warning "Claude Code not installed, skipping Claude setup"
    exit 0
fi

if ! command -v jq &> /dev/null; then
    print_error "jq is required to merge the settings fragment (brew install jq)"
    exit 1
fi

# Symlink the scripts so edits in this repo take effect immediately.
print_info "Linking guard scripts..."
mkdir -p "$CLAUDE_DIR/hooks"
for guard in bash-guard write-guard; do
    ln -sf "$DOTFILES_DIR/claude/hooks/$guard.sh" "$CLAUDE_DIR/hooks/$guard.sh"
    print_success "~/.claude/hooks/$guard.sh -> dotfiles/claude/hooks/$guard.sh"
done

# Merge the fragment into the existing settings, keeping every other key.
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

if ! jq -e . "$SETTINGS" > /dev/null 2>&1; then
    print_error "$SETTINGS is not valid JSON — fix it before rerunning"
    exit 1
fi

# Warn before replacing a hook event this repo also defines. Events the
# fragment does not mention (UserPromptSubmit, Stop, ...) are left alone.
clobbered=$(jq -r --slurpfile f "$FRAGMENT" '
  (.hooks // {}) as $mine
  | ($f[0].hooks | keys) as $ours
  | [ $ours[] | select($mine[.] != null and $mine[.] != $f[0].hooks[.]) ] | join(", ")
' "$SETTINGS")

if [ -n "$clobbered" ]; then
    print_warning "Replacing existing config for: $clobbered"
fi

# Timestamped: a fixed .bak name means the second run overwrites the only
# copy of the settings the user actually started with.
BACKUP="$SETTINGS.$(date +%Y%m%d-%H%M%S).bak"
cp "$SETTINGS" "$BACKUP"
# Merges per event so unrelated hook events already in settings.json survive.
jq --slurpfile f "$FRAGMENT" '
  .hooks = ((.hooks // {}) + $f[0].hooks)
' "$SETTINGS" > "$SETTINGS.tmp"

command mv -f "$SETTINGS.tmp" "$SETTINGS"
print_success "Hooks merged into ~/.claude/settings.json (backup at $(basename "$BACKUP"))"

# Golden-input tests: a guard that silently stops matching is worse than none.
print_info "Running guard tests..."
if bash "$DOTFILES_DIR/claude/test-hooks.sh" > /dev/null 2>&1; then
    print_success "All guard tests pass"
else
    print_error "Guard tests failed — run claude/test-hooks.sh to see which case"
    exit 1
fi
