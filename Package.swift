// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TranslateInstantly",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "TranslateInstantly",
            path: "Sources/TranslateInstantly"
        )
    ]
)
