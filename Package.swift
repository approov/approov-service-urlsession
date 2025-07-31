// swift-tools-version:5.3
import PackageDescription

// The release tag for the branch
let releaseTAG = "3.5.0"
// SDK package version (used for both iOS and watchOS)
let sdkVersion = "3.5.0"

let package = Package(
    name: "ApproovURLSession",
    platforms: [
        .iOS(.v11),
        .watchOS(.v7)
    ],
    products: [
        // Combined library for iOS and watchOS
        .library(
            name: "ApproovURLSession",
            targets: ["ApproovURLSession"]
        ),
        .library(name: "ApproovURLSessionDynamic", type: .dynamic, targets: ["ApproovURLSession"])
    ],
    targets: [
        // Single target for both platforms
        .target(
            name: "ApproovURLSession",
            dependencies: ["Approov"],
            path: "Sources/ApproovURLSession",  // Point to the shared source code
            exclude: ["README.md", "LICENSE"]
        ),
        // Binary target for the merged xcframework
        .binaryTarget(
            name: "Approov",
            url: "https://github.com/approov/approov-ios-sdk/releases/download/\(sdkVersion)/Approov.xcframework.zip",
            checksum: "9a02cb9ca905a9e2e0692047dfd4cdbfd3133c9e4b644bdfe898f7ce1b8d7461"
        )
    ]
)

