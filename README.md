# Meal Planner

A native SwiftUI iPhone app (iOS 17+) for Finnish meal planning and shopping lists. Supports light/dark mode, local JSON persistence, history and migration from the previous Expo app.

- `MealPlanner/`: SwiftUI screens and device storage.
- `MealPlannerCore/`: Foundation-only Swift package and XCTest suite, buildable on Linux.
- `project.yml`: XcodeGen project and signing configuration.

Run `swift build && swift test` inside `MealPlannerCore/`. On a Mac, install Xcode and XcodeGen, run `xcodegen generate`, then open `MealPlanner.xcodeproj`.

See [Mac setup and manual releases](docs/MAC-SETUP.md). Merging does not deploy. The first Swift TestFlight update must be tested over an existing Expo installation to verify data migration.
