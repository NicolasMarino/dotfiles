#!/usr/bin/env bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Detect dotfiles directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
VSCODE_DIR="$HOME/Library/Application Support/Code/User"

print_info "Setting up VS Code..."

# Check if VS Code is installed
if ! command -v code &> /dev/null; then
    print_warning "VS Code CLI (code) is not in your PATH. Skipping VS Code setup."
    exit 0
fi

# Create User directory if it doesn't exist (e.g. fresh install)
if [ ! -d "$VSCODE_DIR" ]; then
    mkdir -p "$VSCODE_DIR"
    print_info "Created VS Code User directory"
fi

# Symlynk settings.json
if [ -f "$DOTFILES_DIR/vscode/settings.json" ]; then
    ln -sf "$DOTFILES_DIR/vscode/settings.json" "$VSCODE_DIR/settings.json"
    print_success "Linked settings.json"
fi

# Install extensions
if [ -f "$DOTFILES_DIR/vscode/extensions.txt" ]; then
    print_info "Installing extensions..."
    
    # Get list of installed extensions
    INSTALLED_EXTENSIONS=$(code --list-extensions)
    
    while IFS= read -r extension || [[ -n "$extension" ]]; do
        if [[ -z "$extension" ]]; then continue; fi
        
        if echo "$INSTALLED_EXTENSIONS" | grep -qi "^$extension$"; then
            echo "  • $extension already installed"
        else
            print_info "  + Installing $extension..."
            code --install-extension "$extension" > /dev/null
        fi
    done < "$DOTFILES_DIR/vscode/extensions.txt"
    
    print_success "Extensions check complete"
fi

echo ""
