// swift-tools-version:5.3
import PackageDescription

// Published upstream v3.0.6 assets; checksums from its GitHub release notes.
let package = Package(
    name: "JizaShell",
    platforms: [.iOS(.v14)],
    products: [.library(name: "JizaShell", targets: ["ios_system","files","shell","text","awk","tar"])],
    targets: [
        .binaryTarget(name: "ios_system", path: "Artifacts/ios_system.xcframework"),
        .binaryTarget(name: "files", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/files.xcframework.zip", checksum: "5db63958f686cc79f107bafd0d50feff32fb2b64d0dd976478c5dd405f7600b0"),
        .binaryTarget(name: "shell", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/shell.xcframework.zip", checksum: "89da3b8bd7f83e42a2311aeac54c38acc7a2f9c2fc0d0d27f75897b393cdfec2"),
        .binaryTarget(name: "text", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/text.xcframework.zip", checksum: "9eef16c23ddaa03d5f28ce2183737b1dbdcfb06e6dc46035a404d9e0f3828604"),
        .binaryTarget(name: "awk", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/awk.xcframework.zip", checksum: "675d3b2e3b5ba60ae1a727528b2cf5e11eda262d404c1e9708dc7e061898df86"),
        .binaryTarget(name: "tar", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/tar.xcframework.zip", checksum: "74146ae19720d3d885d181bce4be2b6b92f11d306a47aa07486bf0dd35fc8f68")
    ]
)

