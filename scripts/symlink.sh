#!/usr/bin/env bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

print_info "Dotfiles directory: $DOTFILES_DIR"
print_info "Creating symlinks..."

# zsh
ln -sf "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
print_success "~/.zshrc -> dotfiles/zsh/.zshrc"

# git
ln -sf "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
print_success "~/.gitconfig -> dotfiles/git/.gitconfig"

ln -sf "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
print_success "~/.gitignore_global -> dotfiles/git/.gitignore_global"

echo ""
print_success "Symlinks created"
print_info "Changes in $DOTFILES_DIR will reflect automatically"
echo ""
