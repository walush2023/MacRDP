// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacRDP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacRDP",
            path: "Sources/MacRDP"
        ),
    ]
)
