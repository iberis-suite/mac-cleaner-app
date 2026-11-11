cask "mac-cleaner-app" do
  version "0.2.2"
  sha256 "d497f4449f7443122844562e845a9494e0935c5097363ed32cf2f7b9f6acc920"

  url "https://github.com/iberis-suite/mac-cleaner-app/releases/download/v#{version}/MacCleaner-#{version}.zip"
  name "Mac Cleaner"
  desc "Menu bar app to monitor and clean your Mac"
  homepage "https://github.com/iberis-suite/mac-cleaner-app"

  depends_on macos: :ventura

  app "Mac Cleaner.app"

  uninstall quit: "com.iberis-suite.mac-cleaner"

  zap trash: [
    "~/Library/Preferences/com.iberis-suite.mac-cleaner.plist",
    "~/Library/LaunchAgents/com.iberis-suite.mac-cleaner.weekly.plist",
    "~/Library/Logs/mac-cleaner-weekly.log",
  ]
end
