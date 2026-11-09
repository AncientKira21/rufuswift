cask "rufuswift" do
  version "4.6.0"
  sha256 :no_check

  url "https://github.com/kasparovabi/rufus/releases/download/v#{version}/Rufus.pkg"
  name "RufuSwift"
  desc "Reliable Multi-Platform USB Formatting & Bootable Drive Creator Utility"
  homepage "https://rufus.ie"

  pkg "Rufus.pkg"

  uninstall pkgutil: "com.ancientkira.rufuswift",
            delete:  "/Applications/Rufus.app"

  zap trash: [
    "~/Library/Preferences/com.ancientkira.rufuswift.plist",
    "~/Library/Saved Application State/com.ancientkira.rufuswift.savedState",
  ]
end
