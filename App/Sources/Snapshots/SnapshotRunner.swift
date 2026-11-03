#if SNAPSHOT_HARNESS
  import AppKit
  import NtfyAppLogic
  import NtfyCore
  import SwiftUI

  /// The entry point of the snapshot build: `NtfyMac --ui-snapshot <outdir>` draws every image of
  /// `SnapshotPlan` in both appearances and exits 0, or non-zero when one could not be drawn.
  /// Without the flag it starts the app as usual.
  @main
  enum SnapshotEntry {
    static func main() {
      let arguments = CommandLine.arguments
      guard let flag = arguments.firstIndex(of: "--ui-snapshot") else {
        NtfyMacApp.main()
        return
      }
      let next = arguments.index(after: flag)
      let output = URL(
        fileURLWithPath: next < arguments.endIndex ? arguments[next] : ".build/snapshots",
        isDirectory: true)
      MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
          let failures = await SnapshotRunner(output: output).run()
          exit(failures == 0 ? 0 : 1)
        }
        application.run()
      }
    }
  }

  @MainActor
  struct SnapshotRunner {
    let output: URL

    /// Draws only the entries whose id contains this (`SNAP_ONLY`), for iterating on one surface.
    private static var only: String { ProcessInfo.processInfo.environment["SNAP_ONLY"] ?? "" }

    /// Draws everything; returns how many images failed.
    func run() async -> Int {
      let fileManager = FileManager.default
      let root = fileManager.temporaryDirectory.appending(
        path: "ntfy-mac-snapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
      do {
        try? fileManager.removeItem(at: output)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
      } catch {
        print("cannot create the output directory: \(error)")
        return 1
      }
      defer { try? fileManager.removeItem(at: root) }
      var failures = 0
      var written = 0
      for spec in SnapshotPlan.specs where Self.only.isEmpty || spec.id.contains(Self.only) {
        do {
          written += try await draw(spec, root: root)
        } catch {
          print("FAILED \(spec.id): \(error)")
          failures += 1
        }
      }
      print("wrote \(written) images to \(output.path)")
      return failures
    }

    /// One world and one window per appearance: a window that switches appearance keeps parts of
    /// its AppKit-backed views (the sidebar) in the old one.
    private func draw(_ spec: SnapshotSpec, root: URL) async throws -> Int {
      var written = 0
      for appearance in SnapshotAppearance.allCases {
        let world = try await SnapshotWorld(SnapshotWorldOptions(for: spec.target), root: root)
        let renderer = SnapshotRenderer(
          content: SnapshotViews.content(for: spec.target, world: world), width: spec.width,
          height: spec.height, isPopover: spec.target.window == nil, appearance: appearance)
        await renderer.settle()
        await SnapshotViews.prepare(spec.target, world: world)
        await renderer.settle(700)
        defer { renderer.close() }
        guard let image = renderer.png() else {
          await world.stop()
          throw SnapshotError.noImage
        }
        let name = spec.fileName(appearance, renderedHeight: image.height)
        try image.data.write(to: output.appending(path: name))
        print(name)
        written += 1
        await world.stop()
      }
      return written
    }
  }

  enum SnapshotError: Error { case noImage }
#endif
