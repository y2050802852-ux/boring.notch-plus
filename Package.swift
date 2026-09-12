// swift-tools-version: 6.0
// Type-check harness: lets the boringNotch app sources be compiled with the
// Swift Package Manager toolchain (swift build) without requiring a full Xcode
// install. Final .app bundling still needs xcodebuild + the Xcode project.
import PackageDescription

let package = Package(
    name: "boringNotchTypecheck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "boringNotch", targets: ["boringNotch"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
        // Vendored copy of KeyboardShortcuts 2.4.0 with #Preview blocks stripped:
        // the Xcode-only PreviewsMacros plugin is unavailable in the Command Line
        // Tools toolchain that this type-check harness uses.
        .package(path: "tools/vendor/KeyboardShortcuts"),
        .package(url: "https://github.com/sindresorhus/Defaults.git", from: "9.0.2"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.2"),
        .package(url: "https://github.com/siteline/swiftui-introspect.git", from: "1.3.0"),
        .package(url: "https://github.com/Lakr233/SkyLightWindow.git", from: "1.0.0"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.5.2"),
        .package(url: "https://github.com/ChimeHQ/AsyncXPCConnection.git", from: "1.3.0"),
        .package(url: "https://github.com/TheBoredTeam/MacroVisionKit.git", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "boringNotch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "SkyLightWindow", package: "SkyLightWindow"),
                .product(name: "Lottie", package: "lottie-spm"),
                .product(name: "AsyncXPCConnection", package: "AsyncXPCConnection"),
                .product(name: "MacroVisionKit", package: "MacroVisionKit"),
            ],
            path: "tools/harness/boringNotch",
            exclude: [
                "Info.plist",
                "boring.m4a",
                "Assets.xcassets",
                "Preview Content",
                "Localizable.xcstrings",
                // Unused legacy file that predates this fork; it does not compile
                // under the newer Swift compiler (missing required init(coder:)).
                "menu/StatusBarMenu.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
