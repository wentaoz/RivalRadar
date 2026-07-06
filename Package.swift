// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RivalRadar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RivalRadar", targets: ["RivalRadar"])
    ],
    targets: [
        .executableTarget(
            name: "RivalRadar",
            path: "Sources/RivalRadar",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security")
            ]
        )
    ]
)
