// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_midi_pro",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-midi-pro", targets: ["flutter_midi_pro"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_midi_pro",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("CoreMIDI"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio")
            ]
        )
    ]
)
