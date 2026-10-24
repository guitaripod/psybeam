// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PsybeamCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PsybeamCore", targets: ["PsybeamCore"])
    ],
    targets: [
        .target(
            name: "PsybeamCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PsybeamCoreTests",
            dependencies: ["PsybeamCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
