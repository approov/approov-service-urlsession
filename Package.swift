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
        .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.0.0")
    ],
    targets: [
        // Single target for both platforms
        .target(
            name: "ApproovURLSession",
            dependencies: [
                "Approov",
                .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers")
            ],
            path: "Sources/ApproovURLSession",  // Point to the shared source code
            exclude: ["README.md", "LICENSE"]
        ),
        // Binary target for the merged xcframework
        .binaryTarget(
            name: "Approov",
            url: "https://github.com/approov/approov-ios-sdk/releases/download/\(sdkVersion)/Approov.xcframework.zip",
            checksum: "c2902922d07df7cdc74b4b5ec70353bfc88339baee7dd94556170c565731da01" // SHA256 checksum of the xcframework zip file
        )
    ]
)

