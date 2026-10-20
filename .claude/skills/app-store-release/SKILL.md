---
name: app-store-release
description: Guide the developer through a manual Xcode archive, TestFlight upload and App Store Connect release, including version/build numbers and metadata.
---

# Release from Xcode

Merging only merges code. The developer performs releases on a Mac; Linux cannot build or submit this iOS app.
Follow [docs/MAC-SETUP.md](../../../docs/MAC-SETUP.md) (repository root `docs/MAC-SETUP.md`).

1. Confirm the commit and green Core CI. Ask the developer to build in Xcode, test on simulator and device, and send simulator screenshots. For the first Swift update, verify migration by installing over the Expo build without deleting it.
2. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` via the issue/PR workflow, then regenerate with `xcodegen generate`. Build numbers must increase above the latest uploaded Expo or Swift build; they no longer auto-increment remotely.
3. The developer opens `MealPlanner.xcodeproj`, signs with team `4X292LGV9D` and bundle ID `fi.muhve.mealplanner`, selects a generic iOS device, then Product → Archive → Distribute App → App Store Connect → Upload.
4. Wait for processing in App Store Connect → Meal Planner → TestFlight. Test the uploaded build on a device. Use the existing App Store Connect app ID `6824632441`.
5. App Store Connect → app → new version: select the processed build, fill What's New and metadata/screenshots, submit for review, then release after approval according to the selected release option. Public release needs the developer's explicit approval.
6. When authorized, tag the released commit (`git tag v<version> <sha> && git push origin v<version>`) and create release notes (`gh release create v<version> --generate-notes`). Follow CLAUDE.md token handling; never print secrets.

Every app change requires a new binary. There are no OTA updates, EAS cloud builds or EAS credentials. Xcode manages signing. A bad build must be replaced by a higher build number; expire it in TestFlight or hold its App Store release.
