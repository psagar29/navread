// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NavRead",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "NavRead", targets: ["NavRead"])
    ],
    targets: [
        .executableTarget(
            name: "NavRead",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "NavReadTests",
            dependencies: ["NavRead"]
        )
    ]
)
