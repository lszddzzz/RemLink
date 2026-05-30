// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RemindersLinkSaverManager",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "RemindersLinkSaverManager", targets: ["RemindersLinkSaverManager"])
  ],
  targets: [
    .executableTarget(
      name: "RemindersLinkSaverManager",
      resources: [
        .copy("Resources")
      ]
    )
  ]
)
