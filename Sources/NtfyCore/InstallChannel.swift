import Foundation

/// How this copy of ntfy-mac was installed; decides who may update it.
public enum InstallChannel: String, Sendable, Codable, Hashable {
  /// Under a Homebrew `Cellar` (or its `opt` link). Only `brew upgrade` updates it.
  case homebrew
  /// The curl installer or a manual download. The app updates itself (Sparkle).
  case direct

  public static func detect(executablePath: String) -> InstallChannel {
    let path = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
    if path.contains("/Cellar/ntfy-mac/") || path.contains("/opt/ntfy-mac/") { return .homebrew }
    return .direct
  }
}
