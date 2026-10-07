// swift-tools-version: 6.2
import PackageDescription

// The upcoming features Xcode groups under "Approachable Concurrency".
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Illuminate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Illuminate", targets: ["Illuminate"]),
    ],
    targets: [
        // Pure, platform-light logic: no AppKit, no window server. Fully unit-tested.
        .target(
            name: "IlluminateCore",
            swiftSettings: approachableConcurrency
        ),
        // The menu-bar app: AppKit, Metal, CoreGraphics. Main actor by default.
        .executableTarget(
            name: "Illuminate",
            dependencies: ["IlluminateCore"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ] + approachableConcurrency,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "IlluminateCoreTests",
            dependencies: ["IlluminateCore"]
        ),
    ]
)
