// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "typst_flutter",
  platforms: [.iOS(.v13)],
  products: [
    .library(name: "typst-flutter", targets: ["typst_flutter"]),
  ],
  targets: [
    .binaryTarget(
      name: "typst_flutter_binary",
      path: "Frameworks/typst_flutter.xcframework"
    ),
    .target(
      name: "typst_flutter",
      dependencies: ["typst_flutter_binary"],
      path: "Sources/typst_flutter"
    ),
  ]
)
