// swift-tools-version: 6.0
import PackageDescription

let releaseTAG = "3.2.3"
let sdkVersioniOS = "3.2.3"
let sdkVersionWatchOS = "3.2.0"

let package = Package(
    name: "ApproovURLSession",
    platforms: [
        .iOS(.v12),
        .watchOS(.v7)
    ],
    products: [
        .library(
            name: "ApproovURLSession",
            targets: ["ApproovURLSession-iOS", "ApproovURLSession-watchOS"]
        )
    ],
    targets: [
        // iOS-specific target using the common code
        .target(
            name: "ApproovURLSession-iOS",
            dependencies: [
                .target(name: "Approov-iOS")
            ],
            path: "Sources/iOS",  // Path for iOS-specific sources
            exclude: ["README.md", "LICENSE"]
        ),
        
        // watchOS-specific target using the common code
        .target(
            name: "ApproovURLSession-watchOS",
            dependencies: [
                .target(name: "Approov-watchOS")
            ],
            path: "Sources/watchOS",  // Path for watchOS-specific sources
            exclude: ["README.md", "LICENSE"]
        ),
        
        // iOS Binary target
        .binaryTarget(
            name: "Approov-iOS",
            url: "https://github.com/approov/approov-ios-sdk/releases/download/\(sdkVersioniOS)/Approov.xcframework.zip",
            checksum: "8382b5ec920f8fbe7a41dd6b32a35a6289ed4a6a2ab7e2ed146ca4b669c8abf4"
        ),
        
        // watchOS Binary target
        .binaryTarget(
            name: "Approov-watchOS",
            url: "https://github.com/approov/approov-watchos-sdk/releases/download/\(sdkVersionWatchOS)/Approov.xcframework.zip",
            checksum: "124fea5b67eaba29985e0cc79884244a76fdbecc705a7d39c62ae97c21e137ac"
        )
    ]
)

