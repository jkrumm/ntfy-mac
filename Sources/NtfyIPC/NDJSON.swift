import Foundation

/// Encodes and decodes newline-delimited JSON frames.
public enum NDJSON {
  private struct VersionProbe: Decodable {
    let protocolVersion: Int
  }

  /// One compact JSON line including the trailing newline.
  public static func encode<Frame: Versioned>(_ frame: Frame) throws(IPCError) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    guard var data = try? encoder.encode(frame) else { throw .malformedFrame }
    data.append(0x0A)
    return data
  }

  /// Decodes one line. The version is checked before the body so that a newer peer's
  /// frame is rejected as unsupported instead of failing on an unknown shape.
  public static func decode<Frame: Versioned>(
    _ type: Frame.Type, from line: Data
  ) throws(IPCError) -> Frame {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let probe = try? decoder.decode(VersionProbe.self, from: line) else {
      throw .malformedFrame
    }
    guard probe.protocolVersion == IPC.protocolVersion else {
      throw .unsupportedProtocolVersion(probe.protocolVersion)
    }
    guard let frame = try? decoder.decode(type, from: line) else { throw .malformedFrame }
    return frame
  }
}
