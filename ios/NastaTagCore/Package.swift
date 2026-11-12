// swift-tools-version: 6.0
import PackageDescription

// Appens logik, utan UI. Delas av appen och Live Activity, och testas med `swift test` på Macen.
let package = Package(
    name: "NastaTagCore",
    defaultLocalization: "sv",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NastaTagCore", targets: ["NastaTagCore"])],
    targets: [
        .target(name: "NastaTagCore", resources: [.copy("metro.json")]),
        .testTarget(name: "NastaTagCoreTests", dependencies: ["NastaTagCore"]),
    ]
)
