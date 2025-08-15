#!/bin/bash

echo "Building SnapPop as app bundle..."

# Clean previous build
rm -rf SnapPop.app

# Create app bundle structure
mkdir -p SnapPop.app/Contents/MacOS
mkdir -p SnapPop.app/Contents/Resources

# Copy Info.plist
cp Info.plist SnapPop.app/Contents/

# Build the executable
swiftc -o SnapPop.app/Contents/MacOS/SnapPop main.swift Sources/*.swift -framework Cocoa -framework Carbon

if [ $? -eq 0 ]; then
    echo "Build successful! SnapPop.app created as background application."
    echo ""
    echo "To run: open SnapPop.app"
    echo "To install: drag SnapPop.app to /Applications"
    echo ""
    echo "Note: You may need to grant accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility"
else
    echo "Build failed!"
    exit 1
fi