// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "URLParser", platforms: [.macOS(.v13)], products: [.executable(name: "URLParser", targets: ["URLParser"])], targets: [.target(name: "URLCore"), .executableTarget(name: "URLParser", dependencies: ["URLCore"]), .testTarget(name: "URLCoreTests", dependencies: ["URLCore"]), .testTarget(name: "URLParserTests", dependencies: ["URLParser"])])
