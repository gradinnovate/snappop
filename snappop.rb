cask "snappop" do
  version "1.2.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/YOUR_USERNAME/snappop/releases/download/v#{version}/SnapPop-#{version}.zip"
  name "SnapPop"
  desc "PopClip-like text selection utility for macOS with advanced detection modes"
  homepage "https://github.com/YOUR_USERNAME/snappop"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true

  app "SnapPop.app"

  postflight do
    # Launch SnapPop after installation
    system_command "/usr/bin/open", args: ["-a", "SnapPop"]
  end

  uninstall quit:       "com.gradinnovate.snappop",
            launchctl:  "com.gradinnovate.snappop",
            delete:     [
              "~/Library/LaunchAgents/com.gradinnovate.snappop.plist",
            ]

  zap trash: [
    "~/Library/Preferences/com.gradinnovate.snappop.plist",
    "~/Library/Caches/com.gradinnovate.snappop",
    "~/Library/Application Support/SnapPop",
  ]
end