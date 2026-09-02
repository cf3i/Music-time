// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EdgePulse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EdgePulse", targets: ["EdgePulse"])
    ],
    targets: [
        .executableTarget(
            name: "EdgePulse",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
