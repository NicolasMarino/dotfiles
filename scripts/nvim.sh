#!/usr/bin/env bash

# Links ~/.config/nvim to this repo's nvim/ (LazyVim + diffview.nvim).
#
# This links a DIRECTORY, not a file, which is why it does not live in
# symlink.sh: scripts/backup.sh only backs up regular files, and `ln -sf` on an
# existing real directory silently creates ~/.config/nvim/nvim instead of
# replacing it. Both cases are handled here.
#
# lazy-lock.json and lazyvim.json are written back into the linked directory —
# that is deliberate, it puts the plugin version pins under version control.
# Plugin payloads live in ~/.local/share/nvim and never touch this repo.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

NVIM_SOURCE="$DOTFILES_DIR/nvim"
NVIM_TARGET="$HOME/.config/nvim"

if ! command -v nvim &> /dev/null; then
    print_warning "Neovim not installed, skipping Neovim setup"
    print_info "The Brewfile declares it: brew bundle --file=$DOTFILES_DIR/brew/Brewfile"
    exit 0
fi

if [ ! -d "$NVIM_SOURCE" ]; then
    print_error "$NVIM_SOURCE not found"
    exit 1
fi

mkdir -p "$HOME/.config"

if [ -L "$NVIM_TARGET" ]; then
    # Already a symlink: re-point it. Nothing to preserve.
    rm "$NVIM_TARGET"
elif [ -e "$NVIM_TARGET" ]; then
    # A real config is in the way. Move rather than copy: leaving the original
    # in place would make the symlink below land inside it.
    BACKUP="$HOME/.dotfiles_backup/nvim.$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$HOME/.dotfiles_backup"
    command mv "$NVIM_TARGET" "$BACKUP"
    print_warning "Existing Neovim config moved to $BACKUP"
fi

ln -s "$NVIM_SOURCE" "$NVIM_TARGET"
print_success "~/.config/nvim -> dotfiles/nvim"

print_info "First launch will bootstrap lazy.nvim and install plugins"
