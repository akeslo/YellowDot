#!/bin/bash

BUNDLE_ID="com.lowtechguys.YellowDot"
APP_NAME="YellowDot"
APP_PATH="/Applications/$APP_NAME.app"

echo "Uninstalling $APP_NAME..."

# Kill running instance
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "Stopping $APP_NAME..."
    pkill -x "$APP_NAME"
    sleep 1
fi

# Remove from Applications
if [ -d "$APP_PATH" ]; then
    echo "Removing $APP_PATH..."
    rm -rf "$APP_PATH"
else
    echo "Not found in /Applications, skipping."
fi

# Remove TCC (permissions) database entries — requires sudo
echo "Removing macOS permissions (requires sudo)..."
sudo tccutil reset All "$BUNDLE_ID" 2>/dev/null && echo "TCC permissions cleared." || echo "No TCC entries found or already cleared."

# Remove Launch Agent (if launch-at-login was set)
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
if [ -f "$LAUNCH_AGENT" ]; then
    echo "Removing launch agent..."
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
fi

# Remove app support / prefs / caches
echo "Removing app data..."
rm -rf "$HOME/Library/Application Support/$APP_NAME"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID"
rm -f  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"

echo ""
echo "Done. $APP_NAME fully removed."
