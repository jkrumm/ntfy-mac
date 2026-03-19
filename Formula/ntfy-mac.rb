class NtfyMac < Formula
  desc "Forward ntfy notifications to macOS Notification Center"
  homepage "https://github.com/jkrumm/homebrew-ntfy-mac"
  version "0.0.0" # updated by CI on each release
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/jkrumm/homebrew-ntfy-mac/releases/download/v#{version}/ntfy-mac-arm64"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # arm64
    end

    on_intel do
      url "https://github.com/jkrumm/homebrew-ntfy-mac/releases/download/v#{version}/ntfy-mac-x64"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # x64
    end
  end

  def install
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    bin.install "ntfy-mac-#{arch}" => "ntfy-mac"
  end

  service do
    run [opt_bin/"ntfy-mac"]
    keep_alive true
    log_path var/"log/ntfy-mac.log"
    error_log_path var/"log/ntfy-mac-error.log"
  end

  test do
    # Binary must handle missing credentials gracefully without crashing
    output = shell_output("#{bin}/ntfy-mac --version 2>&1")
    assert_match "ntfy-mac", output
  end
end
