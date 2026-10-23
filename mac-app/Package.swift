// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CANConnect",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CANConnectCore", targets: ["CANConnectCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "CANConnectCore", dependencies: ["CSQLite"]),
        .testTarget(name: "CANConnectCoreTests", dependencies: ["CANConnectCore", "CSQLite"])
    ]
)
