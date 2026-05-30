// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "Remlink",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "Remlink", targets: ["Remlink"]),
    .executable(name: "RemlinkHelper", targets: ["RemlinkHelper"])
  ],
  targets: [
    .executableTarget(
      name: "Remlink",
      resources: [
        .copy("Resources")
      ]
    ),
    .executableTarget(
      name: "RemlinkHelper"
    )
  ]
)
