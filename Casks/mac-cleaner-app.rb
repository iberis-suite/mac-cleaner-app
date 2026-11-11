cask "mac-cleaner-app" do
  version "0.1.0"
  sha256 "b47c6e9b4422cb2655a5bbe2a34f46e631092550eb0ab8cda2cebc2f24531e45"

  url "https://github.com/iberis-suite/mac-cleaner-app/releases/download/v#{version}/MacCleaner-#{version}.zip"
  name "Mac Cleaner"
  desc "Menu bar app to monitor and clean your Mac"
  homepage "https://github.com/iberis-suite/mac-cleaner-app"

  depends_on macos: ">= :ventura"

  app "Mac Cleaner.app"

  uninstall quit: "com.iberis-suite.mac-cleaner"

  zap trash: [
    "~/Library/Preferences/com.iberis-suite.mac-cleaner.plist",
    "~/Library/LaunchAgents/com.iberis-suite.mac-cleaner.weekly.plist",
    "~/Library/Logs/mac-cleaner-weekly.log",
  ]
end
