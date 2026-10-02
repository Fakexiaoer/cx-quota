// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CXQuota",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CXQuotaCore", targets: ["CXQuotaCore"]),
        .executable(name: "CXQuota", targets: ["CXQuota"]),
    ],
    targets: [
        .target(name: "CXQuotaCore"),
        .executableTarget(name: "CXQuota", dependencies: ["CXQuotaCore"]),
        .testTarget(name: "CXQuotaCoreTests", dependencies: ["CXQuotaCore"]),
    ]
)
