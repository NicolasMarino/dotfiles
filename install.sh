#!/usr/bin/env bash

set -e

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DOTFILES_DIR/scripts/common.sh"

print_info "Dotfiles directory: $DOTFILES_DIR"

# Verify macOS
print_header "Verifying System"

if [[ "$OSTYPE" != "darwin"* ]]; then
    print_error "This script is for macOS only"
    exit 1
fi

print_success "macOS detected"

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    print_success "ARM64 (M1/M2/M3/M4) detected"
    export HOMEBREW_PREFIX="/opt/homebrew"
else
    print_success "Intel detected"
    export HOMEBREW_PREFIX="/usr/local"
fi

# Install Homebrew
print_header "Installing Homebrew"

if ! command -v brew &> /dev/null; then
    print_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    if [[ "$ARCH" == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    
    print_success "Homebrew installed"
else
    print_success "Homebrew already installed"
    print_info "Updating Homebrew..."
    brew update
fi

# Backup existing configs
print_header "Creating Backups"
bash "$DOTFILES_DIR/scripts/backup.sh"

# Create symlinks
print_header "Creating Symlinks"
bash "$DOTFILES_DIR/scripts/symlink.sh"

# Install tools & packages
print_header "Installing Tools"
bash "$DOTFILES_DIR/scripts/install_tools.sh"

# Install from Brewfile
print_header "Installing Homebrew Packages"

if [ -f "$DOTFILES_DIR/brew/Brewfile" ]; then
    print_info "Installing from Brewfile..."
    if brew bundle --file="$DOTFILES_DIR/brew/Brewfile"; then
        print_success "All packages installed"
    else
        print_warning "Some packages failed to install (this is usually okay)"
        print_info "You can install missing packages manually later"
    fi
else
    print_warning "Brewfile not found"
fi

# macOS defaults
print_header "macOS Settings"

read -p "Apply recommended macOS settings? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$DOTFILES_DIR/scripts/macos.sh"
    print_success "Settings applied"
else
    print_info "Skipping macOS settings"
fi

# VS Code Setup
print_header "VS Code Setup"
bash "$DOTFILES_DIR/scripts/vscode.sh"

# Finish
print_header "Installation Complete"

print_success "Dotfiles installed successfully! 🎉"
echo ""
print_info "Next steps:"
echo "  1. Update git/.gitconfig with your name and email"
echo "  2. Customize configurations in $DOTFILES_DIR"
echo ""
print_warning "Backups are stored in ~/.dotfiles_backup/"
echo ""

print_info "Reloading shell to apply changes..."
echo ""
read -p "Press ENTER to reload your shell (or Ctrl+C to exit and reload manually)"

exec zsh
