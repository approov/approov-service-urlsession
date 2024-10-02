// swift-tools-version: 6.0
import PackageDescription

// The release tag for the branch
let releaseTAG = "3.2.3"
// iOS SDK package version
let sdkVersioniOS = "3.2.3"
// watchOS SDK package version
let sdkVersionWatchOS = "3.2.0"

let package = Package(
    name: "ApproovURLSession",
    platforms: [
        .iOS(.v12),
        .watchOS(.v7)
    ],
    products: [
        // iOS Library
        .library(
            name: "ApproovURLSession-iOS",
            targets: ["ApproovURLSession-iOS"]
        ),
        // watchOS Library
        .library(
            name: "ApproovURLSession-watchOS",
            targets: ["ApproovURLSession-watchOS"]
        )
    ],
    targets: [
        // iOS Target
        .target(
            name: "ApproovURLSession-iOS",
            dependencies: ["Approov-iOS"],
            path: "Sources/iOS",  // Set the custom source path for iOS
            exclude: ["README.md", "LICENSE"]
        ),
        .binaryTarget(
            name: "Approov-iOS",
            url: "https://github.com/approov/approov-ios-sdk/releases/download/\(sdkVersioniOS)/Approov.xcframework.zip",
            checksum: "8382b5ec920f8fbe7a41dd6b32a35a6289ed4a6a2ab7e2ed146ca4b669c8abf4"
        ),
        
        // watchOS Target
        .target(
            name: "ApproovURLSession-watchOS",
            dependencies: ["Approov-watchOS"],
            path: "Sources/watchOS",  // Set the custom source path for watchOS
            exclude: ["README.md", "LICENSE"]
        ),
        .binaryTarget(
            name: "Approov-watchOS",
            url: "https://github.com/approov/approov-watchos-sdk/releases/download/\(sdkVersionWatchOS)/Approov.xcframework.zip",
            checksum: "124fea5b67eaba29985e0cc79884244a76fdbecc705a7d39c62ae97c21e137ac"
        )
    ]
)
