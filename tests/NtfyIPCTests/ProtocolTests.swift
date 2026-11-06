import Foundation
import Testing

@testable import NtfyIPC

@Suite struct ProtocolTests {
  private let until = Date(timeIntervalSince1970: 1_793_613_600)

  private func roundTrip<Frame: Versioned & Equatable>(_ frame: Frame) throws -> Frame {
    try NDJSON.decode(Frame.self, from: try NDJSON.encode(frame))
  }

  @Test func everyCommandRoundTripsWithItsPayload() throws {
    let requests = [
      Request(id: "1", command: .ping),
      Request(id: "2", command: .status),
      Request(id: "3", command: .reconnect),
      Request(id: "4", command: .permission),
      Request(
        id: "5", command: .notify,
        notify: NotifyPayload(
          title: "T", body: "B", priority: 5, tags: ["warning"],
          clickURL: URL(string: "https://example.com/x"), dismissAfterSeconds: 7.5)),
      Request(id: "6", command: .ack, ack: MessageTarget(topic: "t", id: "m")),
      Request(id: "7", command: .remind, remind: RemindPayload(topic: "t", id: "m", until: until)),
      Request(id: "8", command: .ackAll, ackAll: AckAllPayload(topic: "t")),
      Request(id: "9", command: .loginItem, loginItem: LoginItemPayload(action: .enable)),
      Request(id: "10", command: .delete, delete: DeletePayload(topic: "t", id: "m")),
      Request(id: "11", command: .delete, delete: DeletePayload(topic: "t")),
      Request(id: "12", command: .update, update: UpdatePayload(check: true)),
      Request(id: "13", command: .update, update: UpdatePayload(check: false)),
    ]
    #expect(Set(requests.map(\.command)) == Set(Command.allCases))
    for request in requests { #expect(try roundTrip(request) == request) }
  }

  @Test func resultsAndErrorCodesRoundTrip() throws {
    let permission = PermissionSummary(
      usable: false, problems: [PermissionIssue(code: "denied", hint: "Allow it")])
    let status = StatusResult(
      connection: "connected", pausedUntil: until, appVersion: "2.0.0", permission: permission)
    let success = Response.success(
      id: "1",
      result: ResultPayload(
        status: status, notify: NotifyResult(posted: true), permission: permission,
        ackAll: AckAllResult(acknowledged: 3), loginItem: LoginItemResult(state: "enabled"),
        delete: DeleteResult(deleted: 2),
        update: UpdateStatusPayload(
          channel: "direct", currentVersion: "2.0.0", latestVersion: "2.1.0",
          updateAvailable: true, reason: "team-mismatch"))
    )
    #expect(try roundTrip(success) == success)
    let failed = Response.failure(id: "2", code: .permissionDenied, message: "no")
    let back = try roundTrip(failed)
    #expect(back == failed)
    #expect(back.code?.rawValue == "permission-denied")
  }

  @Test func unknownFieldsAndErrorCodesAreTolerated() throws {
    let line = Data(
      #"{"code":"from-the-future","extra":{"a":1},"id":"1","protocolVersion":1,"status":"error"}"#
        .utf8)
    let response = try NDJSON.decode(Response.self, from: line)
    #expect(response.code == ErrorCode(rawValue: "from-the-future"))
  }

  @Test func requestsFromBeforeDeleteExistedStillDecode() throws {
    let line = Data(
      #"{"command":"ack","id":"1","protocolVersion":1,"ack":{"topic":"t","id":"m"}}"#.utf8)
    let request = try NDJSON.decode(Request.self, from: line)
    #expect(request.delete == nil)
    #expect(request.ack == MessageTarget(topic: "t", id: "m"))
  }

  @Test func anUpdateStatusNeedsNoLatestVersionOrReason() throws {
    let line = Data(
      #"{"channel":"direct","currentVersion":"2.0.0","updateAvailable":false}"#.utf8)
    let status = try JSONDecoder().decode(UpdateStatusPayload.self, from: line)
    #expect(status == UpdateStatusPayload(channel: "direct", currentVersion: "2.0.0"))
  }

  @Test func notifyNeedsOnlyABody() throws {
    let line = Data(
      #"{"command":"notify","id":"1","notify":{"body":"hi","later":true},"protocolVersion":1}"#
        .utf8)
    let request = try NDJSON.decode(Request.self, from: line)
    #expect(request.notify == NotifyPayload(body: "hi"))
    #expect(request.notify?.priority == 3)
  }

  @Test func notifyWithoutABodyIsMalformed() {
    let line = Data(#"{"command":"notify","id":"1","notify":{},"protocolVersion":1}"#.utf8)
    #expect(throws: IPCError.malformedFrame) { try NDJSON.decode(Request.self, from: line) }
  }

  @Test func futureVersionIsRejectedBeforeTheBodyIsRead() {
    let line = Data(#"{"protocolVersion":2,"somethingNew":[1]}"#.utf8)
    #expect(throws: IPCError.unsupportedProtocolVersion(2)) {
      try NDJSON.decode(Response.self, from: line)
    }
  }
}
