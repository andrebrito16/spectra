cask "spectra-k8s" do
  version "0.1.1"
  sha256 "dd1b94399d46721345ca3fc7418a95b4020a10b8b7b76529c370e9bd6298bd4c"

  url "https://github.com/andrebrito16/spectra/releases/download/v#{version}/Spectra-#{version}.dmg"
  name "Spectra"
  desc "Native macOS Kubernetes IDE"
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
