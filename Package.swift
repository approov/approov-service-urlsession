// swift-tools-version:5.8
import PackageDescription

// The release tag
let releaseTAG = "3.5.2"
// SDK package version (used for both iOS and watchOS)
let sdkVersion = "3.5.0"

let package = Package(
    name: "ApproovURLSession",
    platforms: [
        .iOS(.v11),
        .watchOS(.v9)
    ],
    products: [
        // Combined library for iOS and watchOS
        .library(
            name: "ApproovURLSession",
            targets: ["ApproovURLSession"]
        ),
        .library(
            name: "ApproovURLSessionDynamic",
            type: .dynamic,
            targets: ["ApproovURLSession"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.0.0"),
        .package(url: "https://github.com/approov/approov-ios-sdk.git", from: "3.5.0")
    ],
    targets: [
        // Single target for both platforms
        .target(
            name: "ApproovURLSession",
            dependencies: [
                .product(name: "Approov", package: "approov-ios-sdk"),
                .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers")
            ],
            path: "Sources/ApproovURLSession",  // Point to the shared source code
            exclude: ["README.md", "LICENSE"]
        )
    ]
)

