// swift-tools-version:5.8
import PackageDescription

// The release tag
let releaseTAG = "3.5.3"
// SDK package version (used for both iOS and watchOS)
let sdkVersion = "3.5.1"

let package = Package(
    name: "ApproovURLSessionPackage",
    platforms: [
        .iOS(.v11),
        .watchOS(.v9)
    ],
    products: [
        // Combined library for iOS and watchOS
        .library(
            name: "ApproovURLSessionPackage",
            targets: ["ApproovURLSessionPackage"]
        ),
        .library(
            name: "ApproovURLSessionDynamic",
            type: .dynamic,
            targets: ["ApproovURLSessionPackage"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.0.0"),
        .package(url: "https://github.com/approov/approov-ios-sdk.git", from: "3.5.1")
    ],
    targets: [
        // Single target for both platforms
        .target(
            name: "ApproovURLSessionPackage",
            dependencies: [
                .product(name: "Approov", package: "approov-ios-sdk"),
                .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers")
            ],
            path: "Sources/ApproovURLSession",  // Point to the shared source code
            exclude: ["README.md", "LICENSE"]
        )
    ]
)

