// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpossumKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpossumKit", targets: ["OpossumKit"])
    ],
    targets: [
        .target(
            name: "OpossumKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OpossumKitTests",
            dependencies: ["OpossumKit"],
            resources: [.copy("Fixtures"), .copy("Shim")]
        )
    ]
)
