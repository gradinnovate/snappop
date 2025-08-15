#!/bin/bash

echo "SnapPop Installation Script"
echo "=========================="

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please do not run this script as root/sudo"
    exit 1
fi

# Build the application
echo "Building SnapPop..."
./build.sh

if [ $? -ne 0 ]; then
    echo "Build failed! Exiting..."
    exit 1
fi

# Check if SnapPop.app was created
if [ ! -d "SnapPop.app" ]; then
    echo "SnapPop.app not found! Build may have failed."
    exit 1
fi

# Stop any existing SnapPop instances
echo "Stopping existing SnapPop instances..."
pkill -f "SnapPop" 2>/dev/null || true

# Copy to Applications folder
echo "Installing SnapPop.app to /Applications..."
if [ -d "/Applications/SnapPop.app" ]; then
    echo "Removing existing installation..."
    rm -rf "/Applications/SnapPop.app"
fi

cp -R "SnapPop.app" "/Applications/"

if [ $? -eq 0 ]; then
    echo "✓ SnapPop.app installed successfully"
else
    echo "✗ Failed to install SnapPop.app"
    exit 1
fi

# Set proper permissions
echo "Setting permissions..."
chmod +x "/Applications/SnapPop.app/Contents/MacOS/SnapPop"

# Copy launch daemon plist to the app bundle for reference
cp "com.gradinnovate.snappop.plist" "/Applications/SnapPop.app/Contents/"

echo ""
echo "Installation completed!"
echo ""
echo "To run SnapPop:"
echo "  open /Applications/SnapPop.app"
echo ""
echo "To enable start at login:"
echo "  1. Launch SnapPop"
echo "  2. Click the status bar icon"
echo "  3. Select 'Start at Login'"
echo ""
echo "Note: You may need to grant accessibility permissions in:"
echo "System Preferences > Security & Privacy > Privacy > Accessibility"
echo ""
echo "For crash auto-restart functionality, you can manually install the launch daemon:"
echo "  sudo cp com.gradinnovate.snappop.plist /Library/LaunchDaemons/"
echo "  sudo launchctl load /Library/LaunchDaemons/com.gradinnovate.snappop.plist"
echo ""