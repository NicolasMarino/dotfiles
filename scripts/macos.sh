#!/usr/bin/env bash

set -e

GREEN='\033[0;32m' 
YELLOW='\033[0;33m'     
BLUE='\033[0;34m'   
NC='\033[0m'    

# Function to print a success message in green
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}
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
