// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ntfy-mac",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "NtfyCore", targets: ["NtfyCore"]),
    .executable(name: "ntfy-mac", targets: ["NtfyMacCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
  ],
  targets: [
    .target(name: "NtfyCore"),
    .executableTarget(
      name: "NtfyMacCLI",
      dependencies: [
        "NtfyCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "NtfyCoreTests", dependencies: ["NtfyCore"], path: "tests/NtfyCoreTests"),
  ],
  swiftLanguageModes: [.v6]
)
