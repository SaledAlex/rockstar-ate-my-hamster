// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RockStar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RockStar",
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "RockStarTests", dependencies: ["RockStar"]),
    ]
)
