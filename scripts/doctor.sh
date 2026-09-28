#!/usr/bin/env bash

# Read-only health check for this machine's dotfiles setup. It never modifies
# anything: every finding says what to run to fix it. Broken links exit 1;
# everything else is a warning because the setup still works without it.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

ERRORS=0
WARNINGS=0

fail() {
    print_error "$1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    print_warning "$1"
    WARNINGS=$((WARNINGS + 1))
}

# A managed path must be a symlink whose target exists; a dangling link is
# worse than a missing one because tools fail on it silently.
check_link() {
    local path="$1"
    local display="$path"
    case "$path" in
        "$HOME"/*) display="~${path#"$HOME"}" ;;
    esac
    if [ ! -L "$path" ]; then
        if [ -e "$path" ]; then
            fail "$display is a regular file, not a symlink (run install.sh)"
        else
            fail "$display is missing (run install.sh)"
        fi
    elif [ ! -e "$path" ]; then
        fail "$display is dangling -> $(readlink "$path")"
    else
        print_success "$display -> $(readlink "$path")"
    fi
}

print_header "Symlinks"

for file in .zshrc .zprofile .gitconfig .gitignore_global; do
    check_link "$HOME/$file"
done

while IFS= read -r file; do
    check_link "$HOME/.config/$file"
done < <(config_files "$DOTFILES_DIR")

# claude.sh and vscode.sh skip themselves when their tool is absent, so only
# check their links where the tool's directory exists.
if [ -d "$HOME/.claude" ]; then
    for file in hooks/bash-guard.sh hooks/write-guard.sh statusline.sh subagent-statusline.sh; do
        check_link "$HOME/.claude/$file"
    done
fi

VSCODE_USER="$HOME/Library/Application Support/Code/User"
if [ -d "$VSCODE_USER" ]; then
    check_link "$VSCODE_USER/settings.json"
fi

# nvim is not linked by any script yet, but a stale link to a removed repo
# directory is still worth catching.
if [ -L "$HOME/.config/nvim" ]; then
    check_link "$HOME/.config/nvim"
fi

print_header "Machine-local git config"

for scope in personal work; do
    if [ -f "$DOTFILES_DIR/git/.gitconfig.$scope" ]; then
        print_success "git/.gitconfig.$scope exists"
    else
        warn "git/.gitconfig.$scope missing (copy git/.gitconfig.$scope.sample)"
    fi
done

print_header "PATH"

if command -v zsh &> /dev/null; then
    dupes=$(zsh -i -c 'print -l $path' 2> /dev/null | sort | uniq -d)
    if [ -n "$dupes" ]; then
        warn "Duplicate PATH entries in an interactive zsh:"
        while IFS= read -r entry; do
            print_info "  $entry"
        done <<< "$dupes"
    else
        print_success "No duplicate PATH entries"
    fi
else
    warn "zsh not found, skipping PATH check"
fi

print_header "Homebrew"

BREWFILE="$DOTFILES_DIR/brew/Brewfile"
if command -v brew &> /dev/null; then
    if brew bundle check --file="$BREWFILE" > /dev/null 2>&1; then
        print_success "Everything in the Brewfile is installed"
    else
        warn "Brewfile has missing packages (run: brew bundle --file=brew/Brewfile)"
    fi

    # Without --force, cleanup only lists what it would remove. Its trailing
    # "Would `brew cleanup`" section is stale caches, not drift, so stop there.
    undeclared=""
    count=0
    while IFS= read -r entry; do
        case "$entry" in
            "Would \`brew cleanup\`"*) break ;;
            "Would "*|"Run "*|"") ;;
            *) undeclared+=" $entry"; count=$((count + 1)) ;;
        esac
    done < <(brew bundle cleanup --file="$BREWFILE" 2> /dev/null || true)
    if [ "$count" -gt 0 ]; then
        warn "$count installed package(s) not declared in the Brewfile (dependencies included):"
        print_info " $undeclared"
    else
        print_success "Nothing installed outside the Brewfile"
    fi
else
    warn "brew not found, skipping Brewfile drift check"
fi

print_header "Security"

touch_id=false
if [ -f /etc/pam.d/sudo_local ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so ]]; then
            touch_id=true
        fi
    done < /etc/pam.d/sudo_local
fi
if [ "$touch_id" = true ]; then
    print_success "Touch ID for sudo enabled"
else
    warn "Touch ID for sudo not enabled (run scripts/macos.sh)"
fi

if [ -f "$HOME/.ssh/config" ]; then
    print_success "~/.ssh/config exists"
else
    warn "~/.ssh/config missing (see docs/GIT_CONFIG_GUIDE.md)"
fi

print_header "Repository"

# --git-path resolves hooks through the common dir, so this also works from a
# linked worktree, and it honors core.hooksPath.
hooks_dir=$(git -C "$DOTFILES_DIR" rev-parse --git-path hooks)
case "$hooks_dir" in
    /*) ;;
    *) hooks_dir="$DOTFILES_DIR/$hooks_dir" ;;
esac
if [ -f "$hooks_dir/pre-commit" ]; then
    print_success "pre-commit hook installed"
else
    warn "pre-commit hook not installed (run: pre-commit install)"
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
    print_error "$ERRORS error(s), $WARNINGS warning(s)"
    exit 1
fi
print_success "No errors, $WARNINGS warning(s)"
