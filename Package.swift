// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Volta",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Volta",
            path: "Sources/Volta",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        )
    ]
)
