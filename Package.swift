// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tinycast",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Vendored (see third-party/KeyboardShortcuts) to patch resource-bundle resolution, which
        // otherwise `fatalError`s inside our hand-assembled `.app`. Keep pinned to upstream 2.4.0.
        .package(name: "KeyboardShortcuts", path: "third-party/KeyboardShortcuts")
    ],
    targets: [
        .executableTarget(
            name: "Tinycast",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Tinycast",
            exclude: ["Info.plist", "Tinycast.entitlements", "Assets.xcassets"],
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
