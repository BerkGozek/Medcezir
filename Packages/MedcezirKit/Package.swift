// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MedcezirKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "GitKit", targets: ["GitKit"]),
        .library(name: "MedcezirCore", targets: ["MedcezirCore"]),
    ],
    dependencies: [
        // libgit2 compiled from source as an SPM package (SecureTransport TLS, CommonCrypto hashing).
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2"),
    ],
    targets: [
        .target(name: "GitKit", dependencies: [.product(name: "libgit2", package: "libgit2")]),
        .target(name: "MedcezirCore", dependencies: ["GitKit"]),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"]),
        .testTarget(name: "MedcezirCoreTests", dependencies: ["MedcezirCore"]),
    ]
)
