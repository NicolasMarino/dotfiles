#!/usr/bin/env bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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

BACKUP_DIR="$HOME/.dotfiles_backup"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

FILES_TO_BACKUP=(
    ".zshrc"
    ".gitconfig"
    ".gitignore_global"
)

if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    print_success "Created backup directory: $BACKUP_DIR"
fi

print_info "Creating backups of existing files..."

BACKED_UP=0

for file in "${FILES_TO_BACKUP[@]}"; do
    source_file="$HOME/$file"
    
    if [ -f "$source_file" ] || [ -L "$source_file" ]; then
        if [ -L "$source_file" ]; then
            print_info "$file is a symlink, removing..."
            rm "$source_file"
        else
            backup_file="$BACKUP_DIR/${file}.${TIMESTAMP}"
            cp "$source_file" "$backup_file"
            print_success "Backed up: $file -> ${file}.${TIMESTAMP}"
            BACKED_UP=$((BACKED_UP + 1))
        fi
    fi
done

if [ $BACKED_UP -gt 0 ]; then
    print_success "$BACKED_UP file(s) backed up to $BACKUP_DIR"
else
    print_info "No files to backup"
fi

echo ""
