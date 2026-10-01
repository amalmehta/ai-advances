// swift-tools-version:5.9
// Builds the website's data exporter from the same analysis code the Mac app uses
// ("AI Advances/Data", minus the app-only DataStore). The Mac app itself is built
// from project.yml / "AI Advances.xcodeproj".
import PackageDescription

let package = Package(
    name: "AI Advances",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ai-advances-export", targets: ["ai-advances-export"]),
    ],
    targets: [
        .executableTarget(
            name: "ai-advances-export",
            path: ".",
            exclude: ["AI Advances/Data/DataStore.swift"],
            sources: ["AI Advances/Data", "Exporter"]),
    ]
)
