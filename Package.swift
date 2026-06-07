// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PsybeamKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PsybeamKit", targets: ["PsybeamKit"])
    ],
    targets: [
        .target(
            name: "PsybeamKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PsybeamKitTests",
            dependencies: ["PsybeamKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
