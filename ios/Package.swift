// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DKMadsDMP",
    platforms: [.iOS(.v14), .tvOS(.v14), .macOS(.v12)],
    products: [
        .library(name: "DKMadsDMP", targets: ["DKMadsDMP"]),
    ],
    targets: [
        .target(name: "DKMadsDMP", path: "Sources/DKMadsDMP"),
        .testTarget(
            name: "DKMadsDMPTests",
            dependencies: ["DKMadsDMP"],
            path: "Tests/DKMadsDMPTests"
        ),
    ]
)
