// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CANConnect",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CANConnectCore", targets: ["CANConnectCore"])],
    dependencies: [.package(path: "../shared/DriveLineShared")],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "CANConnectCore", dependencies: ["CSQLite", "DriveLineShared"]),
        .testTarget(name: "CANConnectCoreTests", dependencies: ["CANConnectCore", "CSQLite", "DriveLineShared"])
    ]
)
