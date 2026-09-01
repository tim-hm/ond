// swift-tools-version: 6.2
import PackageDescription

/// One package, several targets: SwiftPM cannot share a tools-version or
/// platform list across packages, and a split would mean one `Package.resolved`
/// per package, each free to pin different versions of the same dependency.
/// Module boundaries are enforced by target dependencies instead — see the
/// note on the OndAPI target.
let package = Package(
    name: "OndCore",
    // macOS lets `swift test` run on the host; without it SwiftPM assumes
    // macOS 10.13 and refuses to link Connect. iOS and watchOS sit at 26 for
    // the Liquid Glass chrome, with no installed base to strand. Tools-version
    // 6.2 exists for `.v26` alone. macOS is 15 for `Color.mix(with:by:)` in
    // OndStyle — a test-host floor, not a platform this ships to.
    platforms: [.iOS(.v26), .macOS(.v15), .watchOS(.v26)],
    products: [
        .library(name: "OndKit", targets: ["OndKit"]),
        .library(name: "OndUI", targets: ["OndUI"]),
        .library(name: "OndStyle", targets: ["OndStyle"]),
    ],
    dependencies: [
        // The Connect runtime. It speaks the Connect, gRPC, and gRPC-Web
        // protocols over URLSession; this app uses gRPC-Web, because that is
        // what tonic-web serves. See docs/transport.md.
        .package(url: "https://github.com/connectrpc/connect-swift", from: "1.0.0"),
        // Declared directly even though connect-swift already depends on it:
        // the generated `.pb.swift` files `import SwiftProtobuf`, and a direct
        // import deserves a direct dependency rather than one that survives only
        // while connect-swift happens to keep it.
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.38.0"),
    ],
    targets: [
        // Deliberately a target and *not* a product. Only OndKit can reach
        // it, so the rule "app code never imports a generated protobuf type"
        // stops being a convention someone has to remember and becomes something
        // the compiler enforces — the app cannot name this module at all.
        .target(
            name: "OndAPI",
            dependencies: [
                .product(name: "Connect", package: "connect-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        // The catalogue export ships in both apps: it is the seed
        // `CachedReferenceRepository` serves before a device has ever reached the
        // server. `.copy`, not `.process`, so the bundled bytes are exactly the
        // ones `mise run check:generated` pins.
        .target(
            name: "OndKit",
            dependencies: ["OndAPI"],
            resources: [.copy("Resources/catalogue.json")]
        ),
        // No dependencies, ever: the design system stays free of domain types, and
        // goal-to-accent mapping belongs to OndStyle. The catalogue must be declared
        // or every colour resolves to nothing — and only Xcode runs actool;
        // `swift build` copies it verbatim, so the palette test reads the JSON.
        // Fonts ride as `.copy`: `Theme.Typeface.register()` finds the TTF by URL.
        .target(name: "OndUI", resources: [
            .process("Colors.xcassets"),
            .copy("Resources/Fonts"),
        ]),
        // Domain-to-token mappings. `OndUI` must never learn what a `TechniqueGoal`
        // is, and a mapping written once per app target is one the phone and the
        // wrist could disagree about silently. Screens stay per-app;
        // `BreathFigureView` is here only because it must be the same drawing on
        // the phone, the wrist, and the Dynamic Island.
        .target(name: "OndStyle", dependencies: ["OndKit", "OndUI"]),
        // Redraws the marketing site's figures from the same geometry the apps
        // draw. A target and not a product, so a development-time tool cannot
        // drift into a shipping binary. Run through `mise run generate:diagrams`.
        .executableTarget(name: "OndDiagrams", dependencies: ["OndKit"]),
        // Exercises the public Swift transport against a running backend. It is
        // a development executable rather than a product shipped by either app.
        .executableTarget(name: "OndLiveSmoke", dependencies: ["OndKit"]),
        // Depends on OndAPI as well as OndKit because it builds proto
        // messages to feed the decoders. That is the boundary being tested, so
        // reaching across it here is the point rather than a leak.
        .testTarget(name: "OndKitTests", dependencies: ["OndKit", "OndAPI"]),
        .testTarget(name: "OndUITests", dependencies: ["OndUI"]),
        .testTarget(name: "OndStyleTests", dependencies: ["OndStyle"]),
    ]
)
