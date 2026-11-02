import Foundation
import Testing

@testable import NtfyIPC

@Suite struct NDJSONTests {
  @Test func requestRoundTrips() throws {
    let request = Request(id: "1", command: .reconnect)
    let line = try NDJSON.encode(request)
    #expect(try NDJSON.decode(Request.self, from: line) == request)
  }

  @Test func responseRoundTrips() throws {
    let response = Response(id: "1", status: .error, message: "boom")
    let line = try NDJSON.encode(response)
    #expect(try NDJSON.decode(Response.self, from: line) == response)
  }

  @Test func frameIsOneLineEndingInNewline() throws {
    let line = try NDJSON.encode(Request(id: "1", command: .ping))
    #expect(line.last == 0x0A)
    #expect(line.dropLast().contains(0x0A) == false)
  }

  @Test func rejectsUnknownProtocolVersion() {
    let future = Data(#"{"command":"ping","id":"1","protocolVersion":99,"extra":true}"#.utf8)
    #expect(throws: IPCError.unsupportedProtocolVersion(99)) {
      try NDJSON.decode(Request.self, from: future)
    }
  }

  @Test func rejectsGarbage() {
    #expect(throws: IPCError.malformedFrame) {
      try NDJSON.decode(Request.self, from: Data("not json".utf8))
    }
  }

  @Test func rejectsKnownVersionWithBadBody() {
    let bad = Data(#"{"command":"explode","id":"1","protocolVersion":1}"#.utf8)
    #expect(throws: IPCError.malformedFrame) { try NDJSON.decode(Request.self, from: bad) }
  }

  @Test func rejectsEmptyLine() {
    #expect(throws: IPCError.malformedFrame) { try NDJSON.decode(Request.self, from: Data()) }
  }

  @Test func rejectsMissingProtocolVersion() {
    let frame = Data(#"{"command":"ping","id":"1"}"#.utf8)
    #expect(throws: IPCError.malformedFrame) { try NDJSON.decode(Request.self, from: frame) }
  }

  @Test(arguments: [#""1""#, "1.5", "null", "true"])
  func rejectsNonIntegerVersion(version: String) {
    let frame = Data(#"{"command":"ping","id":"1","protocolVersion":\#(version)}"#.utf8)
    #expect(throws: IPCError.malformedFrame) { try NDJSON.decode(Request.self, from: frame) }
  }

  @Test func toleratesTrailingNewlineOnDecode() throws {
    let line = try NDJSON.encode(Request(id: "1", command: .ping))
    #expect(try NDJSON.decode(Request.self, from: line).id == "1")
  }
}
