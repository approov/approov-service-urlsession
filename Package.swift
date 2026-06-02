// swift-tools-version:5.8
import Foundation
import PackageDescription
// The release tag for this version of ApproovURLSession
let releaseTAG = "3.5.9"
// SDK package version (used for both iOS and watchOS)
let sdkVersion: Version = "3.5.3"
let useMiniSDK = ProcessInfo.processInfo.environment["APPROOV_USE_MINI_SDK"] == "1"
let miniSDKPath = ProcessInfo.processInfo.environment["APPROOV_MINI_SDK_PATH"] ?? "../core-service-layers-testing/mini-sdk/ios"

let approovPackageName = useMiniSDK ? "mini-sdk-ios" : "approov-ios-sdk"
let packagePlatforms: [SupportedPlatform] = useMiniSDK
    ? [
        .iOS(.v11),
        .watchOS(.v9),
        .macOS(.v13),
    ]
    : [
        .iOS(.v11),
        .watchOS(.v9),
    ]
var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.0.0"),
]
if useMiniSDK {
    packageDependencies.append(.package(name: "mini-sdk-ios", path: miniSDKPath))
} else {
    packageDependencies.append(.package(url: "https://github.com/approov/approov-ios-sdk.git", exact: sdkVersion))
}

var packageTargets: [Target] = [
    .target(
        name: "ApproovURLSessionPackage",
        dependencies: [
            .product(name: "Approov", package: approovPackageName),
            .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers")
        ],
        path: "Sources/ApproovURLSession",
        exclude: ["README.md", "LICENSE", "util/sig/LICENSE"]
    )
]

if useMiniSDK {
    packageTargets.append(
        .testTarget(
            name: "ApproovURLSessionMiniSDKTests",
            dependencies: [
                "ApproovURLSessionPackage",
                .product(name: "Approov", package: "mini-sdk-ios"),
                .product(name: "MiniSDKTestSupport", package: "mini-sdk-ios")
            ],
            path: "Tests/ApproovURLSessionMiniSDKTests"
        )
    )
}

let package = Package(
    name: "ApproovURLSessionPackage",
    platforms: packagePlatforms,
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
    dependencies: packageDependencies,
    targets: packageTargets
)
