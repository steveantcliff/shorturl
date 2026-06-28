// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShortURL",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ShortURL",
            path: "Sources/ShortURL"
        )
    ]
)
