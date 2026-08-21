#!/usr/bin/env bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

BACKUP_DIR="$HOME/.dotfiles_backup"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Every path this repo symlinks over or edits in place must be listed here,
# otherwise the installer overwrites a real config with no way back.
# Paths are relative to $HOME and may contain slashes or spaces.
FILES_TO_BACKUP=(
    ".zshrc"
    ".gitconfig"
    ".gitignore_global"
    "Library/Application Support/Code/User/settings.json"
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
            # Flatten the path: a nested source would otherwise need a
            # directory tree inside the backup dir that does not exist.
            flat_name="${file//\//_}"
            flat_name="${flat_name// /_}"
            backup_file="$BACKUP_DIR/${flat_name}.${TIMESTAMP}"
            cp "$source_file" "$backup_file"
            print_success "Backed up: $file -> ${flat_name}.${TIMESTAMP}"
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
