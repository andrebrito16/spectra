cask "spectra-k8s" do
  version "0.1.0"
  sha256 "4b7da88241d03658b4db91897561d2335142783a555043e5fa8d21f3b605d036"

  url "https://github.com/andrebrito16/spectra/releases/download/v#{version}/Spectra-#{version}.dmg"
  name "Spectra"
  desc "Native macOS Kubernetes IDE"
  homepage "https://github.com/andrebrito16/spectra"

  livecheck do
    url "https://github.com/andrebrito16/spectra/releases"
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
