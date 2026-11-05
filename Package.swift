// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plynn",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.8"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.25.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.3-with-generated-files"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.23.1"),
    ],
    targets: [
        .target(
            name: "PlynnCodeContext",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
            ]),
        .target(
            name: "PlynnKit",
            dependencies: [
                "PlynnCodeContext",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]),
        .executableTarget(
            name: "Plynn",
            dependencies: [
                "PlynnKit",
                "PlynnCodeContext",
                .product(name: "Sparkle", package: "Sparkle"),
            ]),
        .testTarget(
            name: "PlynnCodeContextTests",
            dependencies: ["PlynnCodeContext"]),
        .testTarget(
            name: "PlynnKitTests",
            dependencies: ["PlynnKit"],
            resources: [.copy("Fixtures")]),
    ]
)
