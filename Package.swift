// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RateMatch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/rnine/SimplyCoreAudio.git", from: "4.0.0"),
        // Pinned to a revision, not to `master`: this package has no tags, and tracking a
        // moving branch means someone else's push silently changes what this app builds.
        .package(
            url: "https://github.com/ejbills/mediaremote-adapter.git",
            revision: "5b6afde3f501a3da567e23bf7f23d562938a1809"
        )
    ],
    targets: [
        .executableTarget(
            name: "RateMatch",
            dependencies: [
                .product(name: "SimplyCoreAudio", package: "SimplyCoreAudio"),
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter")
            ],
            path: "Sources/RateMatch"
        )
    ]
)
