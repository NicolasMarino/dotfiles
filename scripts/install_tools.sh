#!/usr/bin/env bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

# Install Oh My Zsh
print_info "Installing Oh My Zsh..."

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    print_success "Oh My Zsh installed"
else
    print_success "Oh My Zsh already installed"
fi

# Install zsh plugins
print_info "Installing zsh plugins..."

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    print_success "zsh-autosuggestions installed"
else
    print_success "zsh-autosuggestions already installed"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    print_success "zsh-syntax-highlighting installed"
else
    print_success "zsh-syntax-highlighting already installed"
fi

# Configure nvm
print_info "Configuring nvm..."

if command -v brew &> /dev/null; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "${HOMEBREW_PREFIX}/opt/nvm/nvm.sh" ] && \. "${HOMEBREW_PREFIX}/opt/nvm/nvm.sh"
    
    if command -v nvm &> /dev/null; then
        print_success "nvm available"
        
        print_info "Installing Node.js LTS..."
        nvm install --lts
        nvm use --lts
        nvm alias default lts/*
        
        print_success "Node.js LTS installed"
        print_info "Node version: $(node --version 2>/dev/null || echo 'N/A')"
        print_info "npm version: $(npm --version 2>/dev/null || echo 'N/A')"
    else
        print_warning "nvm not found, will be installed with Homebrew"
    fi
fi

# Setup fzf
print_info "Setting up fzf (fuzzy finder)..."

if command -v fzf &> /dev/null; then
    if [ ! -f ~/.fzf.zsh ]; then
        ${HOMEBREW_PREFIX}/opt/fzf/install --key-bindings --completion --no-update-rc --no-bash --no-fish
        print_success "fzf key bindings installed"
    else
        print_success "fzf already configured"
    fi
else
    print_warning "fzf not found, will be installed with Homebrew"
fi

echo ""
print_success "Tools installed successfully"
echo ""
