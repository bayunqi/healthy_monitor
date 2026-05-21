// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthyMonitorCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "HealthyMonitorCore", targets: ["HealthyMonitorCore"])
    ],
    targets: [
        .target(
            name: "HealthyMonitorCore",
            dependencies: []
        ),
        .testTarget(
            name: "HealthyMonitorCoreTests",
            dependencies: ["HealthyMonitorCore"]
        )
    ]
)
