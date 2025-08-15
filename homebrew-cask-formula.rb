cask "snappop" do
  version "1.2.0"
  sha256 "d4a8692e308b45b4fdf61a51d6393d90d79ab5934a4824f7be9481b62eeb0186"

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
