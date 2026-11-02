import Foundation

/// How this copy of ntfy-mac was installed. Decides how `update` can update it.
enum InstallMethod: String, Sendable, Encodable {
  case brew
  case app

  /// Homebrew puts the formula under a `Cellar` (or links it through the `opt` prefix).
  static func detect(executablePath: String) -> InstallMethod {
    let path = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
    if path.contains("/Cellar/ntfy-mac/") || path.contains("/opt/ntfy-mac/") { return .brew }
    return .app
  }
}
