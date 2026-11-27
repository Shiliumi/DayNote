// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DayNote",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DayNote", targets: ["DayNote"])
    ],
    targets: [
        .executableTarget(
            name: "DayNote",
            path: "Sources/DayNote"
        )
    ]
)
