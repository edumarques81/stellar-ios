// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StellarVolumiO",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "StellarVolumiO", targets: ["StellarVolumiO"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/socketio/socket.io-client-swift",
            from: "16.1.0"
        )
    ],
    targets: [
        .target(
            name: "StellarVolumiO",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ],
            path: "StellarVolumiO"
        )
    ]
)
