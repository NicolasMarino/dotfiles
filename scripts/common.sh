#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Prints each tracked file under config/, relative to config/. Each one is
# linked to ~/.config/<same path>. symlink.sh and backup.sh both read this list,
# so a new config file cannot be linked without also being backed up. git
# rather than fd because backup.sh runs before Homebrew exists on a fresh Mac,
# and ls-files skips untracked noise such as .DS_Store.
config_files() {
    git -C "$1" ls-files -- config | while IFS= read -r path; do
        echo "${path#config/}"
    done
}
