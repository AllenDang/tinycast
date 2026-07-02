// swift-tools-version:6.1
import PackageDescription

// Vendored copy of sindresorhus/KeyboardShortcuts (2.4.0), carrying a single local patch to
// `Sources/KeyboardShortcuts/Utilities.swift` so localized strings resolve from wherever the host
// app actually ships the resource bundle. Upstream reads them via SwiftPM's generated
// `Bundle.module`, whose accessor `fatalError`s once the executable is hand-assembled into a signed
// `.app` (it only checks the executable's `bundleURL` + a hardcoded build path — never the app's
// `Contents/Resources`). We build releases with `swift build` + `Packaging/make-app.sh` rather than
// the Xcode build system (xcodebuild is unavailable in this toolchain), so we can't rely on Xcode's
// resource-aware accessor; vendoring lets us fix the lookup at the source. The test target and
// Example app are omitted — we ship only the library.
let package = Package(
	name: "KeyboardShortcuts",
	defaultLocalization: "en",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(
			name: "KeyboardShortcuts",
			targets: [
				"KeyboardShortcuts"
			]
		)
	],
	targets: [
		.target(
			name: "KeyboardShortcuts",
			swiftSettings: [
				.swiftLanguageMode(.v5)
			]
		)
	]
)
