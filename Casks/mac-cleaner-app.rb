cask "mac-cleaner-app" do
  version "0.2.1"
  sha256 "7504c501941125c13649c9ce1c9e0dbd4cbfec812965d04c909fe2acf24e8452"

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
