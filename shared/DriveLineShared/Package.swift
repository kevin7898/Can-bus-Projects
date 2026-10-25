// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriveLineShared",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DriveLineShared", targets: ["DriveLineShared"])],
    targets: [
        .target(name: "DriveLineShared"),
        .testTarget(
            name: "DriveLineSharedTests",
            dependencies: ["DriveLineShared"],
            resources: [.copy("Fixtures")]
        )
    ]
)
