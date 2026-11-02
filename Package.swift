// swift-tools-version: 6.2
import PackageDescription

// Warnings are errors for our own targets only; dependencies keep their own settings.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "ntfy-mac",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "NtfyCore", targets: ["NtfyCore"]),
    .library(name: "NtfyClient", targets: ["NtfyClient"]),
    .library(name: "NtfyStore", targets: ["NtfyStore"]),
    .library(name: "NtfyPlatform", targets: ["NtfyPlatform"]),
    .library(name: "NtfyIPC", targets: ["NtfyIPC"]),
    .library(name: "NtfyAppLogic", targets: ["NtfyAppLogic"]),
    .executable(name: "ntfy-mac", targets: ["NtfyMacCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0"),
  ],
  targets: [
    // Pure domain and ports. Depends on nothing.
    .target(name: "NtfyCore", swiftSettings: strict),
    // Adapters. Each one sees the core and nothing else.
    .target(name: "NtfyClient", dependencies: ["NtfyCore"], swiftSettings: strict),
    .target(
      name: "NtfyStore",
      dependencies: ["NtfyCore", .product(name: "GRDB", package: "GRDB.swift")],
      swiftSettings: strict
    ),
    .target(name: "NtfyPlatform", dependencies: ["NtfyCore"], swiftSettings: strict),
    // Versioned CLI <-> app wire protocol. Standalone.
    .target(name: "NtfyIPC", swiftSettings: strict),
    // What the app does with a socket request, behind ports, so tests can drive it. The app
    // target has no test target of its own.
    .target(name: "NtfyAppLogic", dependencies: ["NtfyCore", "NtfyIPC"], swiftSettings: strict),
    // In-memory fakes for every port; linked by test targets only.
    .target(name: "NtfyTesting", dependencies: ["NtfyCore"], swiftSettings: strict),
    // Composition root of the CLI: the one place that wires adapters.
    .executableTarget(
      name: "NtfyMacCLI",
      dependencies: [
        "NtfyCore", "NtfyIPC", "NtfyPlatform", "NtfyClient", "NtfyStore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: strict
    ),
    .testTarget(
      name: "NtfyCoreTests", dependencies: ["NtfyCore"], path: "tests/NtfyCoreTests",
      swiftSettings: strict),
    .testTarget(
      name: "NtfyIPCTests", dependencies: ["NtfyIPC"], path: "tests/NtfyIPCTests",
      swiftSettings: strict),
    .testTarget(
      name: "NtfyAppLogicTests",
      dependencies: ["NtfyAppLogic", "NtfyCore", "NtfyIPC", "NtfyTesting"],
      path: "tests/NtfyAppLogicTests", swiftSettings: strict),
    .testTarget(
      name: "NtfyClientTests", dependencies: ["NtfyClient", "NtfyCore", "NtfyTesting"],
      path: "tests/NtfyClientTests", swiftSettings: strict),
    .testTarget(
      name: "NtfyStoreTests", dependencies: ["NtfyStore", "NtfyCore", "NtfyTesting"],
      path: "tests/NtfyStoreTests", swiftSettings: strict),
    .testTarget(
      name: "NtfyPlatformTests", dependencies: ["NtfyPlatform", "NtfyCore", "NtfyTesting"],
      path: "tests/NtfyPlatformTests", swiftSettings: strict),
    .testTarget(
      name: "NtfyTestingTests", dependencies: ["NtfyTesting", "NtfyCore"],
      path: "tests/NtfyTestingTests", swiftSettings: strict),
    .testTarget(
      name: "NtfyMacCLITests",
      dependencies: ["NtfyMacCLI", "NtfyCore", "NtfyIPC", "NtfyTesting"],
      path: "tests/NtfyMacCLITests", swiftSettings: strict),
  ],
  swiftLanguageModes: [.v6]
)
