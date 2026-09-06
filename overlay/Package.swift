// swift-tools-version: 5.9
import Foundation
import PackageDescription

let info = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist").path
let package = Package(
    name: "UselessPet",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "UselessPet", targets: ["UselessPet"])],
    targets: [
        .executableTarget(name: "UselessPet", resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                                          "-Xlinker", "__info_plist", "-Xlinker", info])]),
        .testTarget(name: "UselessPetTests", dependencies: ["UselessPet"])
    ]
)
