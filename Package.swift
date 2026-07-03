// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tinycast",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Tinycast",
            path: "Tinycast",
            exclude: ["Info.plist", "Tinycast.entitlements", "Assets.xcassets"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
