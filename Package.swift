// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SpendWise",
    products: [
        .library(
            name: "SpendWise",
            targets: ["SpendWise"]
        )
    ],
    targets: [
        .target(
            name: "SpendWise",
            path: "Sources/SpendWise"
        ),
        .testTarget(
            name: "SpendWiseTests",
            dependencies: ["SpendWise"],
            path: "Tests/SpendWiseTests"
        )
    ]
)