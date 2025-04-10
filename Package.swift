// swift-tools-version:5.8
import PackageDescription

// The release tag for the branch
let releaseTAG = "3.4.0"
// SDK package version (used for both iOS and watchOS)
let sdkVersion = "3.4.0"

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
        .library(name: "ApproovURLSessionDynamic", type: .dynamic, targets: ["ApproovURLSession"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.0.0")
    ],
    targets: [
        // Single target for both platforms
        .target(
            name: "ApproovURLSession",
            dependencies: [
                "Approov",
                .product(name: "HTTPStructuredHeaders", package: "swift-http-structured-headers")
            ],
            path: "Sources/ApproovURLSession",  // Point to the shared source code
            exclude: ["README.md", "LICENSE"]
        ),
        // Binary target for the merged xcframework
        .binaryTarget(
            name: "Approov",
            url: "https://github.com/approov/approov-ios-sdk/releases/download/\(sdkVersion)/Approov.xcframework.zip",
            checksum: "9a02cb9ca905a9e2e0692047dfd4cdbfd3133c9e4b644bdfe898f7ce1b8d7461" // SHA256 checksum of the xcframework zip file
        )
    ]
)

