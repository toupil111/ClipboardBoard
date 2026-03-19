// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardBoard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ClipboardBoard",
            targets: ["ClipboardBoard"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ClipboardBoard",
            path: "Sources/ClipboardBoard"
        )
    ]
)
