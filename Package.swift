// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Writer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .target(
            name: "WriterCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .executableTarget(name: "Writer", dependencies: ["WriterCore"]),
        .executableTarget(name: "corecheck", dependencies: ["WriterCore"]),
    ]
)
