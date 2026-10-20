// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MealPlannerCore", platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "MealPlannerCore", targets: ["MealPlannerCore"])],
  targets: [
    .target(name: "MealPlannerCore"),
    .testTarget(name: "MealPlannerCoreTests", dependencies: ["MealPlannerCore"]),
  ])
