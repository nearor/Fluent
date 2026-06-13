// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomoTranslate",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PomoTranslate",
            path: "Sources/PomoTranslate"
        )
    ]
)
