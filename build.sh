#!/bin/bash

echo "Building SnapPop..."

swiftc -o SnapPop main.swift Sources/*.swift -framework Cocoa -framework Carbon

if [ $? -eq 0 ]; then
    echo "Build successful! Run './SnapPop' to start the application."
    echo ""
    echo "Note: You may need to grant accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility"
else
    echo "Build failed!"
    exit 1
fi