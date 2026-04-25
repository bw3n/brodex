// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "brodex-v1",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BrodexV1Frontend", targets: ["BrodexV1Frontend"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.13.0"),
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            revision: "3fdabe5392108d874abae1c1e58e1328ab46f681"
        )
    ],
    targets: [
        .executableTarget(
            name: "BrodexV1Frontend",
            dependencies: [
                "SwiftTerm"
            ],
            path: "Sources/BrodexFrontend"
        ),
        .testTarget(
            name: "BrodexV1FrontendTests",
            dependencies: [
                "BrodexV1Frontend",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/BrodexFrontendTests"
        )
    ]
)
