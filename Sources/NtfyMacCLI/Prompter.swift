import Darwin
import Foundation

/// Asks the user questions. Questions go to stderr so stdout stays data.
protocol Prompting: Sendable {
  /// The answer, the default for an empty one, or nil at end of input.
  func ask(_ question: String, default defaultValue: String?) -> String?
  /// Like `ask`, with the terminal's echo off.
  func askSecret(_ question: String) -> String?
}

struct TerminalPrompter: Prompting {
  func ask(_ question: String, default defaultValue: String?) -> String? {
    let suffix = defaultValue.map { " [\($0)]: " } ?? ": "
    FileHandle.standardError.write(Data((question + suffix).utf8))
    guard let line = readLine() else { return nil }
    let answer = line.trimmingCharacters(in: .whitespacesAndNewlines)
    return answer.isEmpty ? defaultValue : answer
  }

  func askSecret(_ question: String) -> String? {
    FileHandle.standardError.write(Data((question + ": ").utf8))
    var original = termios()
    let canHide = tcgetattr(STDIN_FILENO, &original) == 0
    if canHide {
      var hidden = original
      hidden.c_lflag &= ~tcflag_t(ECHO)
      tcsetattr(STDIN_FILENO, TCSANOW, &hidden)
    }
    defer {
      if canHide { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
      FileHandle.standardError.write(Data("\n".utf8))
    }
    return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
