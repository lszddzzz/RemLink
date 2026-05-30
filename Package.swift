// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Remlink",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "Remlink", targets: ["Remlink"])
  ],
  targets: [
    .executableTarget(
      name: "Remlink",
      resources: [
        .copy("Resources")
      ]
    )
  ]
)
