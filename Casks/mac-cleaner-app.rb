cask "mac-cleaner-app" do
  version "0.2.3"
  sha256 "f131fd2c041b15b9083ff910b57c9f7e35d5de2180b448ee64bb4236a7a1255b"

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
