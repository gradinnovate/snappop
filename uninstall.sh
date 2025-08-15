#!/bin/bash

echo "SnapPop Uninstallation Script"
echo "============================="

# Stop any running SnapPop instances
echo "Stopping SnapPop..."
pkill -f "SnapPop" 2>/dev/null || true

# Remove from Applications
if [ -d "/Applications/SnapPop.app" ]; then
    echo "Removing SnapPop.app from /Applications..."
    rm -rf "/Applications/SnapPop.app"
    echo "✓ SnapPop.app removed"
else
    echo "SnapPop.app not found in /Applications"
fi

# Remove user launch agent
USER_PLIST="$HOME/Library/LaunchAgents/com.gradinnovate.snappop.plist"
if [ -f "$USER_PLIST" ]; then
    echo "Removing user launch agent..."
    launchctl unload "$USER_PLIST" 2>/dev/null || true
    rm -f "$USER_PLIST"
    echo "✓ User launch agent removed"
fi

# Remove system launch daemon (requires sudo)
SYSTEM_PLIST="/Library/LaunchDaemons/com.gradinnovate.snappop.plist"
if [ -f "$SYSTEM_PLIST" ]; then
    echo "System launch daemon found. Removing (requires sudo)..."
    sudo launchctl unload "$SYSTEM_PLIST" 2>/dev/null || true
    sudo rm -f "$SYSTEM_PLIST"
    echo "✓ System launch daemon removed"
fi

# Remove user preferences
echo "Removing user preferences..."
defaults delete com.gradinnovate.snappop 2>/dev/null || true
echo "✓ User preferences removed"

# Clean up log files
echo "Cleaning up log files..."
rm -f /tmp/snappop.log /tmp/snappop.error.log 2>/dev/null || true
echo "✓ Log files cleaned"

echo ""
echo "SnapPop has been completely uninstalled."
echo "You may need to restart your computer to ensure all components are removed."
echo ""