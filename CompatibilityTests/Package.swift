// swift-tools-version:6.0
import PackageDescription

// Source-compatibility fixtures. Each target is written like the code of an app that depends on the service layer,
// once in the Swift 5 and once in the Swift 6 language mode, and is built with warnings treated as errors. A change to
// the service layer that would break, or add warnings to, existing app code in either language mode fails this build.
// These targets are only compiled, never run. See README.md in this directory.
let package = Package(
    name: "ApproovURLSessionCompatibilityTests",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    dependencies: [
        .package(name: "approov-service-urlsession", path: ".."),
    ],
    targets: [
        .target(
            name: "Swift5Consumer",
            dependencies: [.product(name: "ApproovURLSessionPackage", package: "approov-service-urlsession")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warnings-as-errors"]),
            ]
        ),
        .target(
            name: "Swift6Consumer",
            dependencies: [.product(name: "ApproovURLSessionPackage", package: "approov-service-urlsession")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-warnings-as-errors"]),
            ]
        ),
    ]
)
