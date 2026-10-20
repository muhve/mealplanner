# Swift workflow

This is a native Swift/SwiftUI iOS 17+ app. Prioritize mobile usability, accessibility, performance, and light/dark mode. Preserve the Finnish UI copy.

- Codex writes Swift. Claude verifies `MealPlannerCore` with `swift build && swift test`, reviews, and manages issue/PR workflow under CLAUDE.md.
- Core is a local Swift package using only Foundation, with XCTest tests. Keep it Linux-buildable. No SwiftUI, UIKit, Combine, Observation or OSLog in Core; add no dependencies.
- Use SwiftUI and Observation (`@Observable @MainActor`) in the iOS target. Target iOS 17 APIs and keep views simple; Linux cannot typecheck them.
- XcodeGen owns project generation: edit `project.yml`, never the generated `.xcodeproj`. Never edit `ios/` or `android/`.
- Run `swift build && swift test` inside `MealPlannerCore/` before declaring a task done. Claude runs:
  ```bash
  docker run --rm -v "$PWD":/w -w /w/MealPlannerCore swift:6.2-bookworm sh -c 'swift build && swift test'
  ```
- The developer builds and tests the app in Xcode and sends simulator screenshots. Do not claim that Linux syntax checks verify SwiftUI compilation or native behavior.
- Keep the `ruokalista-v1` JSON shape compatible with existing device data. Back up unreadable raw data before replacing it; never publish a change before persistence succeeds.
- Never read, print or copy `.env` or other secrets files.
- Do not commit, push, merge or release unless the current task authorizes it. Never push to main. `yolo` authorizes autopilot to merge only when CI is green and review is clean.
- Merging only merges code. Releases are manual Xcode builds; see `docs/MAC-SETUP.md`.
