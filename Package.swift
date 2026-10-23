// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AetherDisk", platforms: [.macOS(.v14)], products: [
    .executable(name: "AetherDisk", targets: ["AetherDisk"]),
    .executable(name: "aetherdisk-scan", targets: ["AetherDiskScan"])
], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")], targets: [
    .target(name: "AetherDiskCore"),
    .executableTarget(name: "AetherDisk", dependencies: ["AetherDiskCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .executableTarget(name: "AetherDiskScan", dependencies: ["AetherDiskCore"]),
    .testTarget(name: "AetherDiskCoreTests", dependencies: ["AetherDiskCore"])
])
