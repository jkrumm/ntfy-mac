import Foundation

/// The image types a notification attachment may have, told apart by their first bytes: a
/// server's `Content-Type` is a claim, not a fact.
enum ImageFormat: CaseIterable {
  case jpeg, png, gif

  var fileExtension: String {
    switch self {
    case .jpeg: "jpg"
    case .png: "png"
    case .gif: "gif"
    }
  }

  private var signatures: [[UInt8]] {
    switch self {
    case .jpeg: [[0xFF, 0xD8, 0xFF]]
    case .png: [[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]]
    case .gif: [Array("GIF87a".utf8), Array("GIF89a".utf8)]
    }
  }

  static func detect(_ data: Data) -> ImageFormat? {
    allCases.first { format in
      format.signatures.contains { data.starts(with: $0) }
    }
  }
}
