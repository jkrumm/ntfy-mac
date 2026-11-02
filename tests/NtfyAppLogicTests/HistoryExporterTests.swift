import Foundation
import NtfyAppLogic
import NtfyCore
import Testing

@Suite struct HistoryExporterTests {
  private let time = Date(timeIntervalSince1970: 1_700_000_000)

  private func stored(
    _ id: String = "m1", title: String? = "T", body: String = "body", tags: [String] = [],
    click: String? = nil, attachment: MessageAttachment? = nil, read: Bool = false,
    acked: Bool = false
  ) -> StoredMessage {
    StoredMessage(
      message: NtfyMessage(
        id: id, topic: "alerts", time: time, title: title, body: body, priority: .high, tags: tags,
        click: click.flatMap { URL(string: $0) }, attachment: attachment),
      readAt: read ? time : nil, ackedAt: acked ? time : nil)
  }

  private func text(_ data: Data) -> String { String(bytes: data, encoding: .utf8) ?? "" }

  private func records(_ csv: Data) -> [String] {
    text(csv).components(separatedBy: "\r\n")
  }

  // MARK: JSON

  @Test func jsonIsAnArrayOfObjectsWithISOTimesAndSortedKeys() throws {
    let attachment = MessageAttachment(
      url: URL(string: "https://e.com/a.png")!, name: "a.png", mimeType: "image/png", size: 9)
    let data = HistoryExporter.json([
      stored(tags: ["warning"], click: "https://e.com/x", attachment: attachment, read: true)
    ])
    let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let object = try #require(array.first)
    #expect(object["time"] as? String == "2023-11-14T22:13:20Z")
    #expect(object["topic"] as? String == "alerts")
    #expect(object["message"] as? String == "body")
    #expect(object["priority"] as? Int == 4)
    #expect(object["tags"] as? [String] == ["warning"])
    #expect(object["read"] as? Bool == true)
    #expect(object["acknowledged"] as? Bool == false)
    #expect(object["click"] as? String == "https://e.com/x")
    let files = try #require(object["attachments"] as? [[String: Any]])
    #expect(files.first?["url"] as? String == "https://e.com/a.png")
    let json = text(data)
    let keys = ["acknowledged", "attachments", "click", "id", "message", "priority", "read"]
    let positions = keys.compactMap { json.range(of: "\"\($0)\"")?.lowerBound }
    #expect(positions == positions.sorted() && positions.count == keys.count)
  }

  @Test func absentValuesAreNullAndNeverMissing() throws {
    let data = HistoryExporter.json([stored(title: nil)])
    let object = try #require(
      try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    ).first
    #expect(object?["title"] is NSNull)
    #expect(object?["click"] is NSNull)
    #expect((object?["attachments"] as? [Any])?.isEmpty == true)
  }

  @Test func jsonIsStableAndEmptyIsAnEmptyArray() {
    let messages = [stored("a"), stored("b")]
    #expect(HistoryExporter.json(messages) == HistoryExporter.json(messages))
    #expect(text(HistoryExporter.json([])) == "[\n\n]")
  }

  @Test func jsonKeepsUnicodeNewlinesAndQuotesIntact() throws {
    let body = "Größe \u{1F680} \"quoted\"\nline two\t/slash"
    let data = HistoryExporter.json([stored(body: body)])
    let object = try #require(
      try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    ).first
    #expect(object?["message"] as? String == body)
    #expect(text(data).contains("/slash"))
  }

  // MARK: CSV

  @Test func csvHasAHeaderCRLFAndOneRecordPerMessage() {
    let rows = records(HistoryExporter.csv([stored("a"), stored("b", read: true, acked: true)]))
    #expect(rows[0] == HistoryExporter.csvHeader.joined(separator: ","))
    #expect(rows[1] == "alerts,a,2023-11-14T22:13:20Z,T,body,4,,false,false,,")
    #expect(rows[2] == "alerts,b,2023-11-14T22:13:20Z,T,body,4,,true,true,,")
    #expect(rows[3] == "")
    #expect(rows.count == 4)
  }

  @Test func csvWithoutMessagesIsOnlyTheHeader() {
    #expect(
      text(HistoryExporter.csv([])) == HistoryExporter.csvHeader.joined(separator: ",") + "\r\n")
  }

  @Test func csvQuotesCommasQuotesAndLineBreaksPerRFC4180() {
    let csv = text(
      HistoryExporter.csv([stored(title: "a,b", body: "say \"hi\"\r\nnext\nlast")]))
    #expect(csv.contains(",\"a,b\","))
    #expect(csv.contains("\"say \"\"hi\"\"\r\nnext\nlast\""))
  }

  @Test func csvKeepsUnicodeAndTagsAndAttachmentLinks() {
    let attachment = MessageAttachment(url: URL(string: "https://e.com/a.png")!)
    let csv = text(
      HistoryExporter.csv([
        stored(body: "Größe \u{1F680}", tags: ["warning", "skull"], attachment: attachment)
      ]))
    #expect(csv.contains("Größe \u{1F680}"))
    #expect(csv.contains(",warning skull,"))
    #expect(csv.contains(",https://e.com/a.png\r\n"))
  }

  @Test(arguments: ["=1+1", "+1", "-1", "@SUM(A1)", "\tcmd", "\rcmd", "=HYPERLINK(\"x\",\"y\")"])
  func cellsAStreadsheetWouldRunAsAFormulaAreDefused(_ cell: String) {
    let csv = text(HistoryExporter.csv([stored(title: cell, body: cell)]))
    #expect(!csv.contains(",\(cell),"))
    #expect(!csv.contains(",\"\(cell)\","))
    #expect(csv.contains("'" + cell.replacingOccurrences(of: "\"", with: "\"\"")))
  }

  @Test func defusingAppliesToEveryTextCellButLeavesNumbersAndTimesAlone() {
    let csv = text(
      HistoryExporter.csv([stored("=id", title: "-t", tags: ["+tag"], click: "https://e.com")]))
    #expect(csv.contains("alerts,'=id,2023-11-14T22:13:20Z,'-t,body,4,'+tag,"))
    #expect(!csv.contains("''"))
    #expect(text(HistoryExporter.csv([stored(title: "safe=1")])).contains(",safe=1,"))
  }

  // MARK: Export

  @Test func exportNamesTheFileByScopeTimeAndFormat() {
    let json = HistoryExporter.export([stored()], as: .json, scope: "alerts", now: time)
    #expect(json.suggestedFileName == "ntfy-alerts-20231114T221320Z.json")
    #expect(json.format == .json && json.format.mimeType == "application/json")
    let csv = HistoryExporter.export([stored()], as: .csv, scope: nil, now: time)
    #expect(csv.suggestedFileName == "ntfy-all-20231114T221320Z.csv")
    #expect(csv.data == HistoryExporter.csv([stored()]))
    #expect(csv.format.mimeType == "text/csv")
  }
}
