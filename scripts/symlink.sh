#!/usr/bin/env bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Detect dotfiles directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
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
