// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShipNotes",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ShipNotes", targets: ["ShipNotes"]),
    ],
    targets: [
        .executableTarget(
            name: "ShipNotes",
            path: "Sources/ShipNotes",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "ShipNotesTests",
            dependencies: ["ShipNotes"],
            path: "Tests/ShipNotesTests"
        ),
    ]
)
