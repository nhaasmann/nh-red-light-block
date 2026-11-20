// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RedLightBlock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RedLightBlock", targets: ["RedLightBlock"]),
    ],
    targets: [
        .target(name: "RedLightCore"),
        .executableTarget(
            name: "RedLightBlock",
            dependencies: ["RedLightCore"]
        ),
        .testTarget(
            name: "RedLightCoreTests",
            dependencies: ["RedLightCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
