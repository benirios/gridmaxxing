// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MissionGrid",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MissionGrid", targets: ["MissionGrid"])],
    targets: [
        .target(name: "PrivateBridge", linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("ApplicationServices")]),
        .target(name: "GridCore"),
        .executableTarget(name: "MissionGrid", dependencies: ["GridCore", "PrivateBridge"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "GridCoreChecks", dependencies: ["GridCore"], path: "Tests/GridCoreChecks")
    ]
)
