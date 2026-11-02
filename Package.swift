// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hats",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HatsCore", targets: ["HatsCore"])
    ],
    targets: [
        .target(name: "HatsCore"),
        .testTarget(
            name: "HatsCoreTests",
            dependencies: ["HatsCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

// hats supports macOS only. Elsewhere the package is just HatsCore and its
// tests, which CI builds on Linux to keep the core free of macOS-only code.
#if os(macOS)
package.products.append(.executable(name: "hats", targets: ["hats"]))
package.dependencies.append(.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"))
package.targets += [
    .executableTarget(
        name: "hats",
        dependencies: [
            "HatsCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    ),
    // Deliberately depends on nothing: these tests must see only what a user
    // sees, so renaming a field in HatsCore can't quietly keep them passing.
    .testTarget(name: "HatsE2ETests"),
    // Started by those tests in place of a running Claude. `swift test` builds it
    // along with everything else. It makes `swift run` ask which product, and
    // builds that only want hats pass `--product hats` to skip compiling it.
    .executableTarget(name: "hats-e2e-fake", path: "Tests/HatsE2EFake"),
]
#endif
