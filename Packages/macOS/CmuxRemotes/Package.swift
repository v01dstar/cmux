// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxRemotes",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CmuxRemotes", targets: ["CmuxRemotes"])],
    dependencies: [.package(path: "../CmuxFoundation")],
    targets: [
        .target(name: "CmuxRemotes", dependencies: ["CmuxFoundation"], resources: [.copy("Resources/Runtime")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CmuxRemotesTests", dependencies: ["CmuxRemotes", "CmuxFoundation"]),
    ]
)
