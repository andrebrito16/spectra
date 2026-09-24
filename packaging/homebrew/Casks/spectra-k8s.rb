cask "spectra-k8s" do
  version "0.0.2"
  sha256 "545750975dfa8ded0c26208d1f696438a155d8989dd1809320afdbc9e0b12b55"

  url "https://github.com/andrebrito16/spectra/releases/download/v#{version}/Spectra-#{version}.dmg"
  name "Spectra"
  desc "Native Kubernetes IDE"
  homepage "https://github.com/andrebrito16/spectra"

  livecheck do
    url "https://github.com/andrebrito16/spectra/releases"
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Spectra.app"

  zap trash: [
    "~/Library/Application Support/Spectra",
    "~/Library/Preferences/com.andrebritodev.spectra.plist",
    "~/Library/Saved Application State/com.andrebritodev.spectra.savedState",
  ]
end
