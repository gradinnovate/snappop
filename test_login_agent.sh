#!/bin/bash

echo "Testing SnapPop Start at Login functionality"
echo "==========================================="

PLIST_PATH="$HOME/Library/LaunchAgents/com.gradinnovate.snappop.plist"

echo "1. Checking current status..."
if [ -f "$PLIST_PATH" ]; then
    echo "✓ Launch agent plist exists at: $PLIST_PATH"
    echo "Content preview:"
    head -10 "$PLIST_PATH"
    echo ""
    
    echo "2. Checking if loaded in launchctl..."
    if launchctl list | grep -q "com.gradinnovate.snappop"; then
        echo "✓ Launch agent is loaded in launchctl"
    else
        echo "⚠️  Launch agent plist exists but not loaded in launchctl"
    fi
else
    echo "✗ Launch agent plist does not exist"
    echo "  Start at Login is currently disabled"
fi

echo ""
echo "3. LaunchAgents directory contents:"
ls -la "$HOME/Library/LaunchAgents/" | grep snappop || echo "  No SnapPop files found"

echo ""
echo "4. Current launchctl services related to SnapPop:"
launchctl list | grep -i snappop || echo "  No SnapPop services running"

echo ""
echo "Done!"