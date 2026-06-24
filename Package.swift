// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExitIPMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ExitIPCore"),
        .executableTarget(
            name: "ExitIPApp",
            dependencies: ["ExitIPCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "ExitIPCoreTests", dependencies: ["ExitIPCore"]),
    ]
)
