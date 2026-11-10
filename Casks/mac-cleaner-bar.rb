cask "mac-cleaner-bar" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/chaibialaa/mac-cleaner/releases/download/bar-v#{version}/MacCleanerBar-#{version}.zip"
  name "Mac Cleaner"
  desc "Menu bar app for the mac-cleaner CLI"
  homepage "https://github.com/chaibialaa/mac-cleaner"

  depends_on macos: ">= :ventura"
  depends_on formula: "chaibialaa/tap/mac-cleaner"

  app "Mac Cleaner.app"

  uninstall quit: "com.chaibialaa.mac-cleaner-bar"

  zap trash: "~/Library/Preferences/com.chaibialaa.mac-cleaner-bar.plist"
end
