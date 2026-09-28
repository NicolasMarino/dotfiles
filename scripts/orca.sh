#!/usr/bin/env bash
# Install the hourly launchd job that runs orca/orca-reap.sh.
#
#   bash scripts/orca.sh            # install in dry-run mode (logs only)
#   bash scripts/orca.sh --apply    # install in release mode
#   bash scripts/orca.sh --uninstall
#
# Log: ~/Library/Logs/orca-reap.log

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
LABEL="com.nicolasmarino.orca-reap"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/orca-reap.log"
BIN="$HOME/.local/bin/orca-reap"
DOMAIN="gui/$(id -u)"

print_header "Orca worker reaper"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$PLIST" "$BIN"
    print_success "Removed $LABEL"
    exit 0
fi

if ! command -v orca >/dev/null 2>&1; then
    print_warning "orca CLI not found, skipping reaper install"
    exit 0
fi

APPLY=0
if [ "${1:-}" = "--apply" ]; then
    APPLY=1
fi

mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")" "$(dirname "$BIN")"

# launchd cannot read ~/Documents (TCC), so run a copy outside it.
# Re-run this script after editing orca/orca-reap.sh.
install -m 755 "$DOTFILES_DIR/orca/orca-reap.sh" "$BIN"

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$BIN</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "$(command -v orca)"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>ORCA_REAP_APPLY</key>
        <string>$APPLY</string>
    </dict>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$PLIST"
print_success "Installed $LABEL (apply=$APPLY, every hour)"
print_info "Log: $LOG"
