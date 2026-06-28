// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tinycast",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0")
    ],
    targets: [
        .executableTarget(
            name: "Tinycast",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Tinycast",
            exclude: ["Info.plist", "Tinycast.entitlements", "Assets.xcassets"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
