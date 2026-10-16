// swift-tools-version: 6.4
import PackageDescription

/// Settings every target shares: the upcoming features Xcode groups under
/// "Approachable Concurrency", the Swift 7 source checks, and zero tolerance for warnings.
let commonSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .treatAllWarnings(as: .error),
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
            swiftSettings: commonSettings + [
                .strictMemorySafety(),
            ]
        ),
        // The menu-bar app: AppKit, Metal, CoreGraphics. Main actor by default.
        .executableTarget(
            name: "Illuminate",
            dependencies: ["IlluminateCore"],
            swiftSettings: commonSettings + [
                .defaultIsolation(MainActor.self),
            ],
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
            dependencies: ["IlluminateCore"],
            swiftSettings: commonSettings
        ),
    ]
)
