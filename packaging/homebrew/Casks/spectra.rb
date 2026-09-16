cask "spectra" do
  version "0.0.1"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/andrebrito16/spectra/releases/download/v#{version}/Spectra-#{version}.dmg"
  name "Spectra"
  desc "Native macOS Kubernetes IDE"
  homepage "https://github.com/andrebrito16/spectra"

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "Spectra.app"

  zap trash: [
    "~/Library/Application Support/Spectra",
    "~/Library/Preferences/com.andrebritodev.spectra.plist",
    "~/Library/Saved Application State/com.andrebritodev.spectra.savedState",
  ]
end
