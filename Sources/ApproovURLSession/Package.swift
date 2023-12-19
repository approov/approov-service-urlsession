// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription
let releaseTAG = "3.2.0"
let package = Package(
    name: "ApproovURLSession",
    platforms: [.iOS(.v12)],
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
            url: "https://github.com/approov/approov-ios-sdk/releases/download/" + releaseTAG +
"/Approov.xcframework.zip",
            checksum : "c851f845bacfa3c978d12dbf85d7688a3b93e8e25d01f03784fdcb15b8d2beb0"
        )
    ]
)

