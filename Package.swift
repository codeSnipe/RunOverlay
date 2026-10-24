// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RunOverlay",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RunOverlayCore",
            targets: ["RunOverlayCore"]
        ),
        .executable(
            name: "RunOverlayApp",
            targets: ["RunOverlayApp"]
        )
    ],
    targets: [
        .target(
            name: "RunOverlayCore",
            path: "Sources/RunOverlayCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "RunOverlayApp",
            dependencies: ["RunOverlayCore"],
            path: "Sources/RunOverlayApp",
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "RunOverlayCoreTests",
            dependencies: ["RunOverlayCore"],
            path: "Tests/RunOverlayCoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
