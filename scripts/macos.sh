#!/usr/bin/env bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"
print_warning "This script will change macOS system settings"
print_info "You can revert changes from System Preferences"
echo "" 

print_info "Configuring Finder..."

# Show all hidden files in Finder
defaults write com.apple.finder AppleShowAllFiles -bool true
# Show all file extensions in Finder
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
# Show the status bar in Finder windows
defaults write com.apple.finder ShowStatusBar -bool true
# Show the path bar in Finder windows
defaults write com.apple.finder ShowPathbar -bool true
# Set the default search scope to the current folder (SCcf)
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

print_success "Finder configured"

# --- Dock Configuration ---
print_info "Configuring Dock..."

# Enable auto-hide for the Dock
defaults write com.apple.dock autohide -bool true
# Set the auto-hide delay to instant (0 seconds)
defaults write com.apple.dock autohide-delay -float 0
# Set the auto-hide animation speed to faster (0.5 seconds)
defaults write com.apple.dock autohide-time-modifier -float 0.5
# Disable showing recent applications in the Dock
defaults write com.apple.dock mru-spaces -bool false

print_success "Dock configured"

# --- Keyboard & Text Configuration ---
print_info "Configuring keyboard and text input..."

# Fast key repeat (lower is faster; the UI minimums are 2 and 15)
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Repeat held keys instead of showing the accent picker (vim motions)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Disable text substitutions that corrupt code and shell commands
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

print_success "Keyboard and text input configured"

print_info "Configuring Screenshots..."

# Create a dedicated directory for screenshots if it doesn't exist
mkdir -p "${HOME}/Pictures/Screenshots"
# Set the default location for saving screenshots
defaults write com.apple.screencapture location -string "${HOME}/Pictures/Screenshots"
# Set the default screenshot format to PNG
defaults write com.apple.screencapture type -string "png"
# Disable the shadow effect around window screenshots
defaults write com.apple.screencapture disable-shadow -bool true

print_success "Screenshots configured"

print_info "Optimizing performance..."

# Disable automatic window animations globally
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
# Speed up the Mission Control (Exposé) animation duration
defaults write com.apple.dock expose-animation-duration -float 0.1
# Expand the save dialog by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
# Expand the save dialog by default (alternative/additional setting)
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
# Expand the print dialog by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
# Expand the print dialog by default (alternative/additional setting)
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

print_success "Performance optimized"

# --- Miscellaneous Settings ---
print_info "Applying additional settings..."

# Make the user's Library folder visible
chflags nohidden ~/Library
# Make the /Volumes folder visible (requires sudo)
sudo chflags nohidden /Volumes
# Prevent .DS_Store files from being created on network drives
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
# Prevent .DS_Store files from being created on USB drives
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

print_success "Additional settings applied"

# --- Firewall ---
print_info "Configuring application firewall..."

SOCKETFILTERFW="/usr/libexec/ApplicationFirewall/socketfilterfw"
if [ -x "$SOCKETFILTERFW" ]; then
    # Both flags are idempotent: setting an already-on state is a no-op.
    sudo "$SOCKETFILTERFW" --setglobalstate on > /dev/null
    # Stealth mode: do not answer pings or probes on closed ports
    sudo "$SOCKETFILTERFW" --setstealthmode on > /dev/null
    print_success "Firewall and stealth mode enabled"
else
    print_info "socketfilterfw not found, skipping firewall"
fi

# --- Touch ID for sudo ---
print_info "Configuring Touch ID for sudo..."

# sudo_local is included by /etc/pam.d/sudo and survives macOS updates, which
# rewrite /etc/pam.d/sudo itself and would drop an edit made there.
PAM_LOCAL="/etc/pam.d/sudo_local"
PAM_TEMPLATE="/etc/pam.d/sudo_local.template"

# Pure bash so this runs before Homebrew tools exist on a fresh machine.
has_active_pam_tid() {
    local line
    [ -f "$1" ] || return 1
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so ]] && return 0
    done < "$1"
    return 1
}

if has_active_pam_tid "$PAM_LOCAL"; then
    print_info "Touch ID for sudo already enabled"
elif [ ! -f "$PAM_TEMPLATE" ]; then
    print_info "No $PAM_TEMPLATE on this macOS version, skipping Touch ID for sudo"
else
    pam_content=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^#[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so ]]; then
            line="${line#\#}"
        fi
        pam_content+="$line"$'\n'
    done < "$PAM_TEMPLATE"
    printf '%s' "$pam_content" | sudo tee "$PAM_LOCAL" > /dev/null
    print_success "Touch ID for sudo enabled"
fi

# --- Terminal Font Configuration ---
print_info "Configuring terminal fonts..."

# Set Fira Code for Terminal.app
if [ -f "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal" ]; then
    # Create a custom Terminal profile with Fira Code
    defaults write com.apple.Terminal "Default Window Settings" -string "Pro"
    defaults write com.apple.Terminal "Startup Window Settings" -string "Pro"
    
    # Note: Font settings in Terminal.app require manual configuration
    print_info "For Terminal.app: Preferences > Profiles > Font > Change to 'Fira Code'"
fi

# Set Fira Code for iTerm2 (if installed)
if [ -d "/Applications/iTerm.app" ]; then
    defaults write com.googlecode.iterm2 "Normal Font" -string "FiraCode-Regular 13"
    defaults write com.googlecode.iterm2 "Non Ascii Font" -string "FiraCode-Regular 13"
    print_success "iTerm2 font configured"
fi

# Set Fira Code for Warp (if installed)
if [ -d "/Applications/Warp.app" ]; then
    # Warp uses a config file
    WARP_CONFIG="$HOME/.warp/themes/custom.yaml"
    mkdir -p "$HOME/.warp/themes"
    
    if [ ! -f "$WARP_CONFIG" ]; then
        cat > "$WARP_CONFIG" << 'EOF'
font:
  family: "Fira Code"
  size: 13
EOF
        print_success "Warp font configured"
    fi
fi

print_success "Terminal fonts configured"

print_info "Restarting affected applications..."

# Restart Finder to apply changes
killall Finder
# Restart Dock to apply changes
killall Dock
# Restart SystemUIServer (responsible for menu bar items, etc.)
killall SystemUIServer

print_success "Applications restarted"

echo ""
print_success "macOS settings applied successfully"
print_warning "Some settings require a system restart to take full effect"
echo "" 
