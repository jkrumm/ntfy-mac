import Foundation
import Testing

@testable import NtfyClient

@Suite struct ImageFormatTests {
  private static let padding = Data(count: 16)

  @Test(arguments: [
    (Data([0xFF, 0xD8, 0xFF, 0xE0]), ImageFormat.jpeg),
    (Data([0xFF, 0xD8, 0xFF]), .jpeg),
    (Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), .png),
    (Data("GIF87a".utf8), .gif),
    (Data("GIF89a".utf8), .gif),
  ])
  func recognisesTheMagicBytes(prefix: Data, expected: ImageFormat) {
    #expect(ImageFormat.detect(prefix + Self.padding) == expected)
  }

  @Test func extensionsMatchTheFormat() {
    #expect(ImageFormat.jpeg.fileExtension == "jpg")
    #expect(ImageFormat.png.fileExtension == "png")
    #expect(ImageFormat.gif.fileExtension == "gif")
  }

  @Test(arguments: [
    Data(),
    Data([0xFF, 0xD8]),
    Data([0x89, 0x50, 0x4E, 0x47]),
    Data("GIF8".utf8),
    Data("GIF88a".utf8),
    Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8),
    Data("<html></html>".utf8),
    Data("RIFF....WEBPVP8 ".utf8),
  ])
  func rejectsEverythingElse(data: Data) {
    #expect(ImageFormat.detect(data) == nil)
  }
}
