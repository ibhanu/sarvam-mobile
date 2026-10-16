// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sarvam",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Sarvam",
            targets: ["Sarvam"]
        ),
        .library(
            name: "SarvamAudio",
            targets: ["SarvamAudio"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Sarvam",
            dependencies: [],
            path: "packages/swift/Sources/Sarvam",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "SarvamAudio",
            dependencies: ["Sarvam"],
            path: "packages/swift/Sources/SarvamAudio",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "SarvamTests",
            dependencies: ["Sarvam", "SarvamAudio"],
            path: "packages/swift/Tests/SarvamTests"
        )
    ]
)
