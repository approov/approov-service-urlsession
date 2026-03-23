// swift-tools-version:5.8
import PackageDescription
// The release tag for this version of ApproovURLSession
let releaseTAG = "3.5.7"
// SDK package version (used for both iOS and watchOS)
let sdkVersion: Version = "3.5.3"

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
        .package(url: "https://github.com/approov/approov-ios-sdk.git", exact: sdkVersion)
    ],
    targets: [
        .target(
            name: "ApproovURLSessionPackage",
            dependencies: [
                .product(name: "Approov", package: "approov-ios-sdk"),
                .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers")
            ],
            path: "Sources/ApproovURLSession",
            exclude: ["README.md", "LICENSE", "util/sig/LICENSE"]
        ),
        .testTarget(
            name: "ApproovURLSessionPackageTests",
            dependencies: [
                "ApproovURLSessionPackage",
                .product(name: "Approov", package: "approov-ios-sdk")
            ],
            path: "Tests/ApproovURLSessionPackageTests"
        )
    ]
)
