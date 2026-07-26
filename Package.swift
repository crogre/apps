// swift-tools-version: 5.9
import PackageDescription

// This package exists so the pure-Foundation logic in `Tally/Core` can be built and
// tested from the command line — including on Linux, where SwiftUI and SwiftData do not
// exist. The iOS app target compiles the very same files directly (Xcode picks them up
// through the synchronized `Tally` folder), so there is no duplication and no package
// reference to maintain inside the Xcode project.
//
//     swift test
//
let package = Package(
    name: "TallyCore",
    products: [
        .library(name: "TallyCore", targets: ["TallyCore"])
    ],
    targets: [
        .target(name: "TallyCore", path: "Tally/Core"),
        .testTarget(name: "TallyCoreTests", dependencies: ["TallyCore"], path: "Tests/CoreTests"),
    ]
)
