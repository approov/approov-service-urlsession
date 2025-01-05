// swift-tools-version:5.3
import PackageDescription

// The release tag for the branch
let releaseTAG = "3.3.0"
// SDK package version (used for both iOS and watchOS)
let sdkVersion = "3.3.0"

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
            checksum: "8c8737a2cea95e7101f6e05114c37f3f45a600abd196aca05d2c58edb90634dd"
        )
    ]
)

