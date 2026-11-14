import Foundation

/// How this copy of ntfy-mac was installed; decides who may update it.
public enum InstallChannel: String, Sendable, Codable, Hashable {
  /// Under a Homebrew `Cellar` (or its `opt` link): the old formula copy. The cask copy lives in
  /// `/Applications` and is `direct`, because Sparkle updates it (`auto_updates true`).
  case homebrew
  /// The curl installer, a manual download or the Homebrew cask. The app updates itself (Sparkle).
  case direct

  public static func detect(executablePath: String) -> InstallChannel {
    let path = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
    if path.contains("/Cellar/ntfy-mac/") || path.contains("/opt/ntfy-mac/") { return .homebrew }
    return .direct
  }
}
