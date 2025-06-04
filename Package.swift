// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SQLiteORM",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .macCatalyst(.v16)
    ],
    products: [
        // Main library product
        .library(
            name: "SQLiteORM",
            targets: ["SQLiteORM"]
        ),
    ],
    dependencies: [
        // Swift Syntax for macro implementation
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // Main library target
        .target(
            name: "SQLiteORM",
            dependencies: ["SQLiteORMMacros"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        // Macro implementations
        .macro(
            name: "SQLiteORMMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        // Test target
        .testTarget(
            name: "SQLiteORMTests",
            dependencies: [
                "SQLiteORM"
            ]
        ),
    ]
)
