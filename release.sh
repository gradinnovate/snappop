#!/bin/bash

# SnapPop Release Build Script
# Creates a distribution-ready build for Homebrew

set -e

VERSION="1.2.0"
BUILD_DIR="release"
APP_NAME="SnapPop"
DMG_NAME="SnapPop-${VERSION}"

echo "🚀 Building SnapPop Release v${VERSION}"
echo "======================================="

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build the application
echo "🔨 Building application..."
./build.sh

if [ ! -d "SnapPop.app" ]; then
    echo "❌ Build failed - SnapPop.app not found"
    exit 1
fi

# Copy app to release directory
echo "📦 Preparing release package..."
cp -R "SnapPop.app" "$BUILD_DIR/"

# Update version in Info.plist
echo "📝 Updating version to $VERSION..."
plutil -replace CFBundleShortVersionString -string "$VERSION" "$BUILD_DIR/SnapPop.app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$BUILD_DIR/SnapPop.app/Contents/Info.plist"

# Code signing (if certificates are available)
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "🔐 Code signing application..."
    codesign --force --deep --sign "Developer ID Application" "$BUILD_DIR/SnapPop.app"
    echo "✅ Code signing completed"
else
    echo "⚠️  No Developer ID certificate found - skipping code signing"
    echo "   The app will require users to allow it in System Preferences"
fi

# Create ZIP archive for GitHub releases
echo "🗜️  Creating ZIP archive..."
cd "$BUILD_DIR"
zip -r "../${DMG_NAME}.zip" "SnapPop.app"
cd ..

# Calculate SHA256 for Homebrew formula
echo "🔢 Calculating SHA256..."
SHA256=$(shasum -a 256 "${DMG_NAME}.zip" | cut -d ' ' -f 1)

echo ""
echo "✅ Release build completed!"
echo "======================================="
echo "📁 Release files:"
echo "   - ${DMG_NAME}.zip"
echo "   - SHA256: $SHA256"
echo ""
echo "📋 Next steps:"
echo "1. Upload ${DMG_NAME}.zip to GitHub Releases"
echo "2. Update Homebrew Cask formula with new version and SHA256"
echo "3. Submit PR to homebrew-cask repository"
echo ""

# Create Homebrew Cask formula template
echo "🍺 Creating Homebrew Cask formula..."
cat > homebrew-cask-formula.rb << EOF
cask "snappop" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/YOUR_USERNAME/snappop/releases/download/v#{version}/SnapPop-#{version}.zip"
  name "SnapPop"
  desc "PopClip-like text selection utility for macOS"
  homepage "https://github.com/YOUR_USERNAME/snappop"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "SnapPop.app"

  postflight do
    system_command "/usr/bin/open", args: ["-a", "SnapPop"]
  end

  uninstall quit:       "com.gradinnovate.snappop",
            launchctl:  "com.gradinnovate.snappop",
            delete:     [
              "~/Library/LaunchAgents/com.gradinnovate.snappop.plist",
            ]

  zap trash: [
    "~/Library/Preferences/com.gradinnovate.snappop.plist",
  ]
end
EOF

echo "📄 Homebrew Cask formula created: homebrew-cask-formula.rb"
echo ""
echo "🔧 Remember to:"
echo "   - Replace YOUR_USERNAME with your GitHub username"
echo "   - Test the formula locally before submitting"
echo "   - Update the repository URL in the formula"