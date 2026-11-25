// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Scholara",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Scholara", targets: ["ScholaraApp"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "ScholaraCore", dependencies: ["CSQLite", "ZIPFoundation"]),
        .executableTarget(name: "ScholaraApp", dependencies: ["ScholaraCore"]),
        .executableTarget(name: "ScholaraChecks", dependencies: ["ScholaraCore", "ZIPFoundation"], path: "Tests/ScholaraCoreTests", resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
