// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription
let releaseTAG = "3.0.0"
let package = Package(
    name: "ApproovURLSession",
    platforms: [.iOS(.v10)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "ApproovURLSession",
            targets: ["ApproovURLSession", "Approov"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ApproovURLSession",
            exclude: ["README.md", "LICENSE"]
            ),
        .binaryTarget(
            name: "Approov",
            url: "https://github.com/approov/approov-ios-sdk-bitcode/releases/download/" + releaseTAG + "/Approov.xcframework.zip",
            checksum : "ee9e432bca8060f109d00c04bbd28766dda6a38612d5056d737f54000e01f311"
        )
    ]
)
