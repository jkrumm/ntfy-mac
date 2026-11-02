import NtfyCore

/// `subscribe` without arguments: the topics the app listens to, and where each comes from.
struct TopicListing {
  let environment: CLIEnvironment
  let out: Output

  init(_ environment: CLIEnvironment, _ out: Output) {
    self.environment = environment
    self.out = out
  }

  private struct Entry: Encodable {
    let name: String
    let local: Bool
  }

  private struct Report: Encodable {
    /// `environment` when NTFY_TOPICS replaces everything, else `account`.
    let source: String
    /// False when the server could not be asked; only local topics are listed then.
    let serverReachable: Bool
    let topics: [Entry]
    let invalid: [String]
    let overflow: [String]
  }

  func show() async throws {
    let settings = try await environment.settings()
    var discovered: [String] = []
    var reachable = true
    if settings.topics == nil {
      let source = environment.topicSource(settings.url, settings.token, settings.allowInsecure)
      do {
        discovered = try await source.subscribedTopics()
      } catch {
        reachable = false
        out.note("Could not fetch the server's topics (\(error.cliMessage)); showing local ones.")
      }
    }
    let resolved = TopicResolver.resolve(
      selection: TopicSelection(override: settings.topics, extra: settings.extraTopics),
      discovered: discovered)
    let entries = resolved.topics.map {
      Entry(name: $0, local: settings.extraTopics.contains($0) && !discovered.contains($0))
    }
    let report = Report(
      source: settings.topics == nil ? "account" : "environment", serverReachable: reachable,
      topics: entries, invalid: resolved.invalid, overflow: resolved.overflow)
    out.result(report, text: text(report))
  }

  private func text(_ report: Report) -> String {
    var lines = ["Subscribed topics", ""]
    lines.append(
      report.source == "environment"
        ? "  Source: NTFY_TOPICS environment variable (full override)"
        : "  Source: auto-discovery + local additions")
    lines.append("")
    lines += report.topics.map { "  \($0.name)\($0.local ? " (local)" : "")" }
    if report.topics.isEmpty { lines.append("  (none)") }
    if !report.invalid.isEmpty {
      lines += ["", "  Ignored (invalid names): \(report.invalid.joined(separator: ", "))"]
    }
    if !report.overflow.isEmpty {
      lines += ["", "  Over the 150-topic limit: \(report.overflow.joined(separator: ", "))"]
    }
    lines += [
      "", "Add a topic:    ntfy-mac subscribe <topic>",
      "Remove a topic: ntfy-mac unsubscribe <topic>",
      "Reset to auto:  ntfy-mac subscribe reset",
    ]
    return lines.joined(separator: "\n")
  }
}
