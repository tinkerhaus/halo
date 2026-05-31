// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Halo", targets: ["Halo"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Halo",
            dependencies: [.product(name: "Yams", package: "Yams")],
            path: "Sources/Halo",
            resources: [.process("Resources")]
        )
    ]
)
